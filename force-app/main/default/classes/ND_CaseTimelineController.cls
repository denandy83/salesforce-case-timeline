public without sharing class ND_CaseTimelineController {

    public class TimelineItem implements Comparable {
        @AuraEnabled public String id;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public String title;
        @AuraEnabled public String body;        
        @AuraEnabled public String historyBody; 
        @AuraEnabled public Boolean hasHistory;
        @AuraEnabled public String author;
        @AuraEnabled public String category;    
        @AuraEnabled public Boolean isInternal; 
        @AuraEnabled public Boolean isOutgoing; 
        @AuraEnabled public Boolean historyExpanded = false;
        @AuraEnabled public String recordUrl;

        public Integer compareTo(Object compareTo) {
            TimelineItem other = (TimelineItem) compareTo;
            if (this.createdDate < other.createdDate) return 1;
            if (this.createdDate > other.createdDate) return -1;
            return 0;
        }
    }

    // --- CONFIGURATION WRAPPER ---
    public class TimelineConfig {
        @AuraEnabled public Integer batchSize { get; set; }
        @AuraEnabled public Boolean debugMode { get; set; }
        @AuraEnabled public Boolean showToast { get; set; }
        @AuraEnabled public Integer pollingInterval { get; set; }
        @AuraEnabled public Boolean defaultEmail { get; set; }
        @AuraEnabled public Boolean defaultInternal { get; set; }
        @AuraEnabled public Boolean defaultPublic { get; set; }
        @AuraEnabled public Boolean defaultSystem { get; set; }
        @AuraEnabled public Integer visibleCharLimit { get; set; } 
        @AuraEnabled public Boolean expandByDefault { get; set; }
        
        public TimelineConfig() {
            this.batchSize = 10;
            this.debugMode = false;
            this.showToast = false;
            this.pollingInterval = 15000;
            this.defaultEmail = true;
            this.defaultInternal = true;
            this.defaultPublic = true;
            this.defaultSystem = false;
            this.visibleCharLimit = 1950; 
            this.expandByDefault = false;
        }
    }

    @AuraEnabled(cacheable=true)
    public static TimelineConfig getTimelineConfig() {
        TimelineConfig configWrapper = new TimelineConfig();
        
        try {
            Custom_Configuration__c dbConfig = [
                SELECT Batch_Size__c, Debug_Mode__c, Loading_Times_Toast__c, 
                       Polling_Interval__c, Show_Email_Default__c, 
                       Show_Internal_Default__c, Show_Public_Default__c, 
                       Show_Sytem_Default__c, Visible_Character_Limit__c,
                       Expand_by_default__c
                FROM Custom_Configuration__c 
                WHERE Active__c = true 
                LIMIT 1
            ];
            
            if (dbConfig != null) {
                if (dbConfig.Batch_Size__c != null) configWrapper.batchSize = (Integer)dbConfig.Batch_Size__c;
                configWrapper.debugMode = dbConfig.Debug_Mode__c;
                configWrapper.showToast = dbConfig.Loading_Times_Toast__c;
                if (dbConfig.Polling_Interval__c != null) configWrapper.pollingInterval = (Integer)dbConfig.Polling_Interval__c * 1000; 
                configWrapper.defaultEmail = dbConfig.Show_Email_Default__c;
                configWrapper.defaultInternal = dbConfig.Show_Internal_Default__c;
                configWrapper.defaultPublic = dbConfig.Show_Public_Default__c;
                configWrapper.defaultSystem = dbConfig.Show_Sytem_Default__c;
                if (dbConfig.Visible_Character_Limit__c != null) {
                    configWrapper.visibleCharLimit = (Integer)dbConfig.Visible_Character_Limit__c;
                }
                configWrapper.expandByDefault = dbConfig.Expand_by_default__c;
            }
        } catch (Exception e) {
            System.debug('No active configuration found, using defaults.');
        }
        
        return configWrapper;
    }

    @AuraEnabled
    public static List<TimelineItem> getTimelineData(Id caseId, DateTime beforeDate, Integer limitSize) {
        if (limitSize == null || limitSize < 1) limitSize = 10;
        if (beforeDate == null) beforeDate = DateTime.now().addSeconds(1);

        List<EmailMessage> emailCandidates = [
            SELECT Id, Subject, HtmlBody, TextBody, MessageDate, FromName, CreatedBy.Name, Incoming 
            FROM EmailMessage 
            WHERE ParentId = :caseId 
            AND Status != '5' 
            AND MessageDate < :beforeDate
            ORDER BY MessageDate DESC
            LIMIT :limitSize
        ];

        List<FeedItem> feedCandidates = [
            SELECT Id, Body, CreatedDate, CreatedBy.Name, Type, Visibility, Title, Status, IsRichText,
            (SELECT FieldName, OldValue, NewValue FROM FeedTrackedChanges),
            (SELECT Id, RecordId, Type, Title FROM FeedAttachments WHERE Type IN ('InlineImage', 'Content'))
            FROM FeedItem 
            WHERE ParentId = :caseId 
            AND Type != 'EmailMessageEvent'
            AND CreatedDate < :beforeDate 
            ORDER BY CreatedDate DESC
            LIMIT :limitSize
        ];

        List<SObject> combinedRaw = new List<SObject>();
        combinedRaw.addAll((List<SObject>)emailCandidates);
        combinedRaw.addAll((List<SObject>)feedCandidates);

        List<RawItemWrapper> wrappers = new List<RawItemWrapper>();
        for(SObject obj : combinedRaw) {
            wrappers.add(new RawItemWrapper(obj));
        }
        wrappers.sort();

        List<EmailMessage> finalEmails = new List<EmailMessage>();
        List<FeedItem> finalFeeds = new List<FeedItem>();

        Integer count = 0;
        for(RawItemWrapper w : wrappers) {
            if (count >= limitSize) break;
            if (w.obj instanceof EmailMessage) {
                finalEmails.add((EmailMessage)w.obj);
            } else {
                finalFeeds.add((FeedItem)w.obj);
            }
            count++;
        }

        Map<Id, ConnectApi.FeedItem> connectMap = new Map<Id, ConnectApi.FeedItem>();
        List<String> idsToEnrich = new List<String>();
        
        for (FeedItem fi : finalFeeds) {
            if (fi.Type == 'TextPost' || fi.Type == 'ContentPost' || fi.Type == 'LinkPost' || fi.Type == 'AdvancedTextPost') {
                idsToEnrich.add(fi.Id);
            }
        }

        if (!idsToEnrich.isEmpty()) {
            try {
                List<ConnectApi.BatchResult> results = ConnectApi.ChatterFeeds.getFeedElementBatch(null, idsToEnrich);
                for (ConnectApi.BatchResult result : results) {
                    if (result.isSuccess()) {
                        Object res = result.getResult();
                        if (res instanceof ConnectApi.FeedItem) {
                            ConnectApi.FeedItem cfi = (ConnectApi.FeedItem)res;
                            connectMap.put(cfi.id, cfi);
                        }
                    }
                }
            } catch (Exception e) { System.debug('ConnectAPI Error: ' + e.getMessage()); }
        }

        return processItems(finalEmails, finalFeeds, connectMap);
    }

    public class RawItemWrapper implements Comparable {
        public SObject obj;
        public DateTime sortDate;
        
        public RawItemWrapper(SObject o) {
            this.obj = o;
            if (o instanceof EmailMessage) {
                this.sortDate = ((EmailMessage)o).MessageDate;
            } else {
                this.sortDate = ((FeedItem)o).CreatedDate;
            }
        }
        
        public Integer compareTo(Object compareTo) {
            RawItemWrapper other = (RawItemWrapper) compareTo;
            if (this.sortDate < other.sortDate) return 1;
            if (this.sortDate > other.sortDate) return -1;
            return 0;
        }
    }

    @TestVisible 
    private static List<TimelineItem> processItems(List<EmailMessage> emails, List<FeedItem> feedItems, Map<Id, ConnectApi.FeedItem> connectMap) {
    
        List<TimelineItem> combinedList = new List<TimelineItem>();
        Map<String, String> statusMap = getStatusMap();
        
        String baseUrl = getBaseUrl();
        String fileBaseUrl = getFileBaseUrl();
        
        // Maps to hold file details
        Map<String, String> documentIdToVersionId = new Map<String, String>();
        Map<String, String> versionIdToDocumentId = new Map<String, String>();
        Map<String, String> docIdToTitle = new Map<String, String>();
        Map<String, String> docIdToExtension = new Map<String, String>();
        
        Set<String> contentDocIds = new Set<String>();
        Set<String> contentVersionIds = new Set<String>();

        for (FeedItem cf : feedItems) {
            if (cf.FeedAttachments != null && !cf.FeedAttachments.isEmpty()) {
                for (FeedAttachment fa : cf.FeedAttachments) {
                    // Safe Cast and Check
                    String rId = (String)fa.RecordId;
                    if ((fa.Type == 'InlineImage' || fa.Type == 'Content') && String.isNotBlank(rId)) {
                        if (rId.startsWith('069')) {
                            contentDocIds.add(rId);
                        } else if (rId.startsWith('068')) {
                            contentVersionIds.add(rId);
                        }
                    }
                }
            }
        }

        if (!contentDocIds.isEmpty() || !contentVersionIds.isEmpty()) {
            try {
                // FIXED: Query Title and FileExtension here
                List<ContentVersion> versions = [SELECT Id, ContentDocumentId, Title, FileExtension
                                                FROM ContentVersion 
                                                WHERE (ContentDocumentId IN :contentDocIds OR Id IN :contentVersionIds)
                                                AND IsLatest = true];
                
                for (ContentVersion cv : versions) {
                    documentIdToVersionId.put(cv.ContentDocumentId, cv.Id);
                    versionIdToDocumentId.put(cv.Id, cv.ContentDocumentId);
                    
                    // Map details by Document ID (primary key for display)
                    docIdToTitle.put(cv.ContentDocumentId, cv.Title);
                    docIdToExtension.put(cv.ContentDocumentId, cv.FileExtension);
                    
                    // Also map by Version ID just in case
                    docIdToTitle.put(cv.Id, cv.Title);
                    docIdToExtension.put(cv.Id, cv.FileExtension);
                }
            } catch (Exception e) {
                System.debug('ERROR querying ContentVersion: ' + e.getMessage());
            }
        }

        // --- PROCESS EMAILS ---
        Set<Id> emailIds = new Set<Id>();
        for (EmailMessage em : emails) {
            emailIds.add(em.Id);
        }
        
        Map<Id, List<ContentDocumentLink>> emailAttachments = new Map<Id, List<ContentDocumentLink>>();
        if (!emailIds.isEmpty()) {
            // FIXED: Added ContentDocument.FileExtension to query
            for (ContentDocumentLink link : [SELECT Id, ContentDocumentId, LinkedEntityId, ContentDocument.Title, ContentDocument.FileExtension
                                             FROM ContentDocumentLink 
                                             WHERE LinkedEntityId IN :emailIds]) {
                if (!emailAttachments.containsKey(link.LinkedEntityId)) {
                    emailAttachments.put(link.LinkedEntityId, new List<ContentDocumentLink>());
                }
                emailAttachments.get(link.LinkedEntityId).add(link);
            }
        }
        
        for(EmailMessage em : emails) {
            TimelineItem item = new TimelineItem();
            item.id = em.Id;
            item.createdDate = em.MessageDate;
            item.category = 'Email'; 
            item.isInternal = false;
            item.isOutgoing = (em.Incoming == false);
            item.title = (em.Subject != null) ? '✉️ ' + em.Subject : 'No Subject';
            item.author = (em.Incoming == false && em.CreatedBy != null) ? em.CreatedBy.Name : em.FromName;
            item.recordUrl = '/' + em.Id;

            if (String.isNotBlank(em.HtmlBody)) {
                item.body = em.HtmlBody; 
            } else {
                item.body = (em.TextBody != null) ? em.TextBody.replace('\n', '<br/>') : '';
            }
            item.hasHistory = false;
            item.historyBody = ''; 
            
            if (emailAttachments.containsKey(em.Id)) {
                List<String> attachmentCards = new List<String>();
                for (ContentDocumentLink link : emailAttachments.get(em.Id)) {
                    // FIXED: Pass real extension
                    attachmentCards.add(getAttachmentCardHtml(link.ContentDocumentId, link.ContentDocument.Title, link.ContentDocument.FileExtension));
                }
                
                if (!attachmentCards.isEmpty()) {
                    String attachmentSection = '<div style="margin-top:10px; padding-top:6px; border-top:1px solid #e5e5e5;">' + String.join(attachmentCards, '') + '</div>';
                    item.body += attachmentSection;
                    if (String.isNotBlank(item.historyBody)) {
                        item.historyBody += attachmentSection;
                    }
                }
            }
            combinedList.add(item);
        }

        // --- PROCESS FEED ITEMS ---
        for (FeedItem soqlFeedItem : feedItems) {
            
            if (soqlFeedItem.Status == 'Draft') continue;
            if (soqlFeedItem.Type == 'EmailMessageEvent') continue;

            TimelineItem item = new TimelineItem();
            item.id = soqlFeedItem.Id;
            item.createdDate = soqlFeedItem.CreatedDate;
            item.hasHistory = false;
            item.recordUrl = '/' + soqlFeedItem.Id;

            ConnectApi.FeedItem connectFeedItem = (connectMap != null) ? connectMap.get(soqlFeedItem.Id) : null;

            if (connectFeedItem != null && connectFeedItem.actor != null) {
                item.author = connectFeedItem.actor.name;
            } else {
                item.author = (soqlFeedItem.CreatedBy != null) ? soqlFeedItem.CreatedBy.Name : 'System';
            }

            Boolean isSystemType = (soqlFeedItem.Type == 'TrackedChange' || soqlFeedItem.Type == 'CreateRecordEvent' || soqlFeedItem.Type == 'ActivityEvent' || soqlFeedItem.Type == 'CaseCommentPost' || soqlFeedItem.Type == 'ChangeStatusPost' || (soqlFeedItem.CreatedBy != null && soqlFeedItem.CreatedBy.Name == 'Automated Process') || soqlFeedItem.Title == 'SYSTEM' || soqlFeedItem.Title == 'MILESTONE' || soqlFeedItem.Title == 'Owner Changed');

            if (isSystemType) {
                item.category = 'System';
                item.isInternal = true; 
                if (soqlFeedItem.Title == 'SYSTEM' || soqlFeedItem.Title == 'MILESTONE' || soqlFeedItem.Title == 'Owner Changed') {
                    item.title = '⚙️ ' + soqlFeedItem.Title;
                } else {
                    item.title = '⚙️ ' + formatSystemTitle(soqlFeedItem.Type);
                }
            } else if (soqlFeedItem.Visibility == 'AllUsers') {
                item.category = 'Public';
                item.isInternal = false; 
                item.title = '💬 Public Post';
            } else {
                item.category = 'Internal';
                item.isInternal = true; 
                item.title = '🔒 Internal Note';
            }

            if (connectFeedItem != null) {
                String formattedBody = soqlFeedItem.Body != null ? soqlFeedItem.Body : '';
                Map<String, String> mentionReplacements = new Map<String, String>();
                Map<String, String> mentionProtectionMap = new Map<String, String>();
                Integer mentionIndex = 0;
                
                if (connectFeedItem.body != null && connectFeedItem.body.messageSegments != null) {
                    for (ConnectApi.MessageSegment segment : connectFeedItem.body.messageSegments) {
                        if (segment instanceof ConnectApi.MentionSegment) {
                            ConnectApi.MentionSegment m = (ConnectApi.MentionSegment)segment;
                            String mentionText = m.text; 
                            String mentionLink = '<a href="/' + m.record.id + '" class="mention-link" data-record-id="' + m.record.id + '" style="color:#0176d3; font-weight:bold; text-decoration:none;">' + m.text + '</a>';
                            
                            String placeholder = '[[[[MENTION_' + mentionIndex + ']]]]';
                            mentionProtectionMap.put(placeholder, mentionLink);
                            mentionReplacements.put(mentionText, placeholder);
                            mentionIndex++;
                        }
                    }
                }
                
                for (String mentionText : mentionReplacements.keySet()) {
                    formattedBody = formattedBody.replace(mentionText, mentionReplacements.get(mentionText));
                }
                
                String cleanBody = fixRelativeImageUrls(formattedBody, baseUrl, fileBaseUrl, documentIdToVersionId);
                
                // FIXED: Pass maps to helper
                cleanBody = appendFeedAttachments(cleanBody, soqlFeedItem, versionIdToDocumentId, docIdToTitle, docIdToExtension);

                String parsedResult = null;
                if (String.isNotBlank(formattedBody) && (formattedBody.containsIgnoreCase('feedEvent') || formattedBody.contains('{"fu"'))) {
                    parsedResult = parseFeedEventString(formattedBody, statusMap);
                }

                if (parsedResult != null) {
                    item.body = parsedResult;
                } else if (String.isNotBlank(cleanBody)) {
                    item.body = cleanHtml(cleanBody, true);
                    item.body = makeImagesClickable(item.body, versionIdToDocumentId);
                    
                    for (String placeholder : mentionProtectionMap.keySet()) {
                        item.body = item.body.replace(placeholder, mentionProtectionMap.get(placeholder));
                    }
                } else {
                    item.body = '<i>[' + soqlFeedItem.Type + ']</i>';
                }
            } 
            else {
                String formattedBody = soqlFeedItem.Body != null ? soqlFeedItem.Body : '';
                String cleanBody = fixRelativeImageUrls(formattedBody, baseUrl, fileBaseUrl, documentIdToVersionId);
                
                // FIXED: Pass maps to helper
                cleanBody = appendFeedAttachments(cleanBody, soqlFeedItem, versionIdToDocumentId, docIdToTitle, docIdToExtension);

                String parsedResult = null;
                if (String.isNotBlank(formattedBody) && (formattedBody.containsIgnoreCase('feedEvent') || formattedBody.contains('{"fu"'))) {
                    parsedResult = parseFeedEventString(formattedBody, statusMap);
                }

                if (parsedResult != null) {
                    item.body = parsedResult;
                }
                else if (soqlFeedItem.FeedTrackedChanges != null && !soqlFeedItem.FeedTrackedChanges.isEmpty() && String.isBlank(formattedBody)) {
                    item.body = processTrackedChanges(soqlFeedItem.FeedTrackedChanges, statusMap);
                } 
                else if (String.isNotBlank(cleanBody)) {
                    item.body = cleanHtml(cleanBody, true); 
                    item.body = makeImagesClickable(item.body, versionIdToDocumentId);
                } else {
                    item.body = '<i>[' + soqlFeedItem.Type + ']</i>';
                }
            }

            combinedList.add(item);
        }

        combinedList.sort();
        return combinedList;
    }

    // --- NEW HELPER: Generates the attachment card HTML with explicit Extension support ---
    private static String getAttachmentCardHtml(String docId, String fileName, String fileExtension) {
        if (fileName == null) fileName = 'Attachment';
        
        String fileIcon = '📄'; 
        // Use extension if available, otherwise fallback to filename check
        String checkStr = (String.isNotBlank(fileExtension)) ? '.' + fileExtension.toLowerCase() : fileName.toLowerCase();
        
        if (checkStr.endsWith('png') || checkStr.endsWith('jpg') || checkStr.endsWith('jpeg') || checkStr.endsWith('gif') || checkStr.endsWith('webp')) {
            fileIcon = '🖼️';
        } else if (checkStr.endsWith('pdf')) {
            fileIcon = '📕';
        } else if (checkStr.endsWith('doc') || checkStr.endsWith('docx')) {
            fileIcon = '📘';
        } else if (checkStr.endsWith('xls') || checkStr.endsWith('xlsx') || checkStr.endsWith('csv')) {
            fileIcon = '📊';
        } else if (checkStr.endsWith('ppt') || checkStr.endsWith('pptx')) {
            fileIcon = '📙';
        } else if (checkStr.endsWith('txt')) {
            fileIcon = '📝';
        } else if (checkStr.endsWith('zip') || checkStr.endsWith('rar') || checkStr.endsWith('7z')) {
            fileIcon = '📦';
        }
        
        return '<a href="/lightning/r/ContentDocument/' + docId + '/view" class="image-preview-link" data-doc-id="' + docId + '" style="display:inline-flex; align-items:center; margin:4px 8px 4px 0; padding:6px 10px; background:#f3f2f2; border:1px solid #c9c7c5; border-radius:3px; text-decoration:none; color:#0176d3; font-size:0.8125rem; cursor:pointer;">' +
            '<span style="margin-right:6px; font-size:1.1em;">' + fileIcon + '</span>' + fileName +
            '</a>';
    }

    // --- NEW HELPER: Appends Feed Attachments using lookup maps for Title/Ext ---
    private static String appendFeedAttachments(String body, FeedItem soqlFeedItem, Map<String, String> versionIdToDocumentId, Map<String, String> docIdToTitle, Map<String, String> docIdToExtension) {
        String result = body;
        List<String> attachmentCards = new List<String>();
        
        if (soqlFeedItem.FeedAttachments != null && !soqlFeedItem.FeedAttachments.isEmpty()) {
            for (FeedAttachment fa : soqlFeedItem.FeedAttachments) {
                String rId = (String)fa.RecordId;
                if ((fa.Type == 'Content' || fa.Type == 'InlineImage') && String.isNotBlank(rId)) {
                    String docId = null;
                    
                    if (rId.startsWith('069')) {
                        docId = rId;
                    } 
                    else if (rId.startsWith('068')) {
                        if (versionIdToDocumentId.containsKey(rId)) {
                            docId = versionIdToDocumentId.get(rId);
                        }
                    }

                    if (String.isNotBlank(docId)) {
                        // Retrieve explicit title and extension from our maps
                        String realTitle = docIdToTitle.get(docId);
                        String realExt = docIdToExtension.get(docId);
                        
                        // Fallback to FeedAttachment title if map failed
                        if (String.isBlank(realTitle)) realTitle = fa.Title;
                        
                        attachmentCards.add(getAttachmentCardHtml(docId, realTitle, realExt));
                    }
                }
            }
        }

        if (!attachmentCards.isEmpty()) {
            String attachmentSection = '<div style="margin-top:10px; padding-top:6px; border-top:1px solid #e5e5e5;">' + String.join(attachmentCards, '') + '</div>';
            result = (String.isNotBlank(result) ? result : '') + attachmentSection;
        }
        return result;
    }

    @AuraEnabled
    public static Boolean checkForNewItems(Id caseId, DateTime lastCheckDate) {
        if (caseId == null || lastCheckDate == null) return false;
        
        Integer count = [SELECT Count()
                        FROM FeedItem 
                        WHERE ParentId = :caseId 
                        AND CreatedDate > :lastCheckDate
                        AND Type IN ('TextPost', 'EmailMessageEvent', 'ContentPost', 'LinkPost')
                        LIMIT 1];
                        
        return count > 0;
    }

    private static String processTrackedChanges(List<FeedTrackedChange> changes, Map<String, String> statusMap) {
        List<String> result = new List<String>();
        for (FeedTrackedChange ftc : changes) {
            String field = (ftc.FieldName != null) ? ftc.FieldName : 'Field';
            String label = field;
            try {
                if (field.startsWith('Case.')) {
                    String fieldApiName = field.substring(5);
                    Schema.DescribeFieldResult fieldDescribe = Schema.SObjectType.Case.fields.getMap().get(fieldApiName).getDescribe();
                    label = fieldDescribe.getLabel();
                } else {
                     if (Schema.SObjectType.Case.fields.getMap().containsKey(field)) {
                        label = Schema.SObjectType.Case.fields.getMap().get(field).getDescribe().getLabel();
                     }
                }
            } catch (Exception e) {
                if (field.startsWith('Case.')) label = field.substring(5);
            }
            
            String oldV = String.valueOf(ftc.OldValue);
            String newV = String.valueOf(ftc.NewValue);
            
            if (field == 'feedEvent' && String.isNotBlank(oldV)) {
                try {
                    Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(oldV);
                    if (root.containsKey('fu')) {
                        List<Object> fieldUpdates = (List<Object>) root.get('fu');
                        for (Object itemObj : fieldUpdates) {
                            Map<String, Object> updateMap = (Map<String, Object>) itemObj;
                            String actualField = String.valueOf(updateMap.get('fn'));
                            String actualOldV = String.valueOf(updateMap.get('ov'));
                            String actualNewV = String.valueOf(updateMap.get('nv'));
                            
                            if (actualField == 'Status' && statusMap != null) {
                                if (statusMap.containsKey(actualOldV)) actualOldV = statusMap.get(actualOldV);
                                if (statusMap.containsKey(actualNewV)) actualNewV = statusMap.get(actualNewV);
                            }
                            
                            if (actualOldV == null || actualOldV == 'null') actualOldV = '(blank)';
                            if (actualNewV == null || actualNewV == 'null') actualNewV = '(blank)';
                            
                            result.add('<b>' + actualField + '</b>: ' + actualOldV + ' &rarr; ' + actualNewV);
                        }
                    }
                } catch (Exception e) {
                    result.add('<b>' + label + '</b>: <i>(Updated)</i>');
                }
            } else {
                if ((field == 'Status' || field == 'Case.Status') && statusMap != null) {
                    if (oldV != null && statusMap.containsKey(oldV)) oldV = statusMap.get(oldV);
                    if (newV != null && statusMap.containsKey(newV)) newV = statusMap.get(newV);
                }
                if (oldV == null || oldV == 'null') oldV = '(blank)';
                if (newV == null || newV == 'null') newV = '(blank)';
                
                if (oldV == '(blank)' && newV == '(blank)') {
                    result.add('<b>' + label + '</b>: <i>(Updated)</i>');
                } else {
                    result.add('<b>' + label + '</b>: ' + oldV + ' &rarr; ' + newV);
                }
            }
        }
        return String.join(result, '<br/>');
    }

    @TestVisible
    private static String fixRelativeImageUrls(String html, String baseUrl, String fileBaseUrl, Map<String, String> documentIdToVersionId) {
        if (String.isBlank(html)) return html;
        String result = html;
        
        Pattern p0 = Pattern.compile('(?i)<img([^>]*?)src="sfdc://([^"]+)"');
        Matcher m0 = p0.matcher(result);
        while (m0.find()) {
            String fullMatch = m0.group();
            String beforeSrc = m0.group(1);
            String contentDocumentId = m0.group(2);
            String contentVersionId = documentIdToVersionId.get(contentDocumentId);
            
            String replacement;
            if (String.isNotBlank(contentVersionId)) {
                replacement = '<img' + beforeSrc + 'src="' + fileBaseUrl + '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + contentVersionId + '&operationContext=CHATTER&contentId=' + contentDocumentId + '"';
            } else {
                replacement = fullMatch;
            }
            result = result.replace(fullMatch, replacement);
        }
        
        if (String.isNotBlank(baseUrl)) {
            Pattern p1 = Pattern.compile('(?i)<img([^>]*?)src="(/sfc/[^"]+)"');
            Matcher m1 = p1.matcher(result);
            while (m1.find()) {
                String fullMatch = m1.group();
                String beforeSrc = m1.group(1);
                String relativeUrl = m1.group(2);
                String replacement = '<img' + beforeSrc + 'src="' + baseUrl + relativeUrl + '"';
                result = result.replace(fullMatch, replacement);
            }
        }
        return result;
    }

    @TestVisible
    private static String getFileBaseUrl() {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        if (baseUrl.contains('.my.salesforce.com')) {
            baseUrl = baseUrl.replace('.my.salesforce.com', '.file.force.com');
        } else if (baseUrl.contains('.lightning.force.com')) {
            baseUrl = baseUrl.replace('.lightning.force.com', '.file.force.com');
        }
        if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        return baseUrl;
    }

    @TestVisible
    private static String getBaseUrl() {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        return baseUrl;
    }

    @TestVisible
    private static String parseFeedEventString(String cleanBody, Map<String, String> statusMap) {
        try {
            Integer idxStart = cleanBody.indexOf('{');
            Integer idxEnd = cleanBody.lastIndexOf('}');
            if (idxStart == -1 || idxEnd == -1 || idxEnd <= idxStart) return null;

            String jsonPart = cleanBody.substring(idxStart, idxEnd + 1);
            jsonPart = jsonPart.replace('"', '"').replace('"', '"'); 
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonPart);
            
            if (root.containsKey('fu')) {
                List<Object> fieldUpdates = (List<Object>) root.get('fu');
                for (Object itemObj : fieldUpdates) {
                    Map<String, Object> updateMap = (Map<String, Object>) itemObj;
                    String field = String.valueOf(updateMap.get('fn')); 
                    String oldV = String.valueOf(updateMap.get('ov')); 
                    String newV = String.valueOf(updateMap.get('nv')); 
                    
                    if (field == 'Status' || field == 'Case.Status') {
                        if (statusMap.containsKey(oldV)) oldV = statusMap.get(oldV);
                        if (statusMap.containsKey(newV)) newV = statusMap.get(newV);
                        if (String.isBlank(oldV) || oldV == 'null') oldV = '(blank)';
                        if (String.isBlank(newV) || newV == 'null') newV = '(blank)';
                        return '<b>Status</b>: ' + oldV + ' &rarr; ' + newV;
                    }
                }
            }
            return null;
        } catch (Exception e) { return null; }
    }

    @TestVisible
    private static Map<String, String> getStatusMap() {
        Map<String, String> m = new Map<String, String>();
        m.put('1', 'New');
        m.put('2', 'On Hold');
        m.put('3', 'Closed');
        m.put('6', 'Open');
        m.put('7', 'Working');
        m.put('8', 'Waiting for Customer');
        m.put('9', 'Solved');
        try {
            Schema.DescribeFieldResult fieldResult = Case.Status.getDescribe();
            for(Schema.PicklistEntry f : fieldResult.getPicklistValues()) {
                m.put(f.getValue(), f.getLabel());
                m.put(f.getLabel(), f.getLabel());
            }
        } catch (Exception e) { }
        return m;
    }

    @TestVisible
    private static String formatSystemTitle(String type) {
        if (type == 'TrackedChange') return 'Field Update';
        if (type == 'ChangeStatusPost') return 'Status Changed';
        if (type == 'CreateRecordEvent') return 'Record Created';
        return type;
    }
    
    @TestVisible
    private static String makeImagesClickable(String html, Map<String, String> versionIdToDocId) {
        if (String.isBlank(html)) return html;
        String result = html;
        Pattern imgPattern = Pattern.compile('(?i)<img([^>]*?)src="([^"]+)"([^>]*?)>');
        Matcher imgMatcher = imgPattern.matcher(result);
        
        List<String> matches = new List<String>();
        List<String> replacements = new List<String>();
        
        while (imgMatcher.find()) {
            String fullMatch = imgMatcher.group();
            String beforeSrc = imgMatcher.group(1);
            String srcUrl = imgMatcher.group(2);
            String afterSrc = imgMatcher.group(3);
            
            String versionId = null;
            if (srcUrl.contains('versionId=')) {
                Integer startIdx = srcUrl.indexOf('versionId=') + 10;
                Integer endIdx = srcUrl.indexOf('&', startIdx);
                if (endIdx == -1) endIdx = srcUrl.length();
                versionId = srcUrl.substring(startIdx, endIdx);
            }
            
            String docId = versionIdToDocId.get(versionId);
            String replacement;
            if (String.isNotBlank(docId)) {
                replacement = '<a href="/lightning/r/ContentDocument/' + docId + '/view" class="image-preview-link" data-doc-id="' + docId + '" style="display:block; max-width:80%;"><img' + beforeSrc + 'src="' + srcUrl + '"' + afterSrc + ' style="max-width:100%; cursor:pointer;"></a>';
            } else {
                String fullUrl = srcUrl.replaceAll('([?&])rendition=[^&]*(&|$)', '$1').replaceAll('[?&]$', '');
                replacement = '<a href="' + fullUrl + '" target="_blank" style="display:block; max-width:80%;"><img' + beforeSrc + 'src="' + srcUrl + '"' + afterSrc + ' style="max-width:100%; cursor:pointer;"></a>';
            }
            matches.add(fullMatch);
            replacements.add(replacement);
        }
        for (Integer i = 0; i < matches.size(); i++) {
            result = result.replace(matches[i], replacements[i]);
        }
        return result;
    }

    private static String cleanHtml(String html, Boolean shouldLinkify) {
        if (String.isBlank(html)) return '';
        html = html.replace('<html', '<div').replace('</html>', '</div>')
                   .replace('<body', '<div').replace('</body>', '</div>')
                   .replace('<!DOCTYPE html>', '');
        
        Map<String, String> codeMap = new Map<String, String>();
        Integer codeIndex = 0;
        Pattern codePattern = Pattern.compile('(?is)<code>(.*?)</code>');
        Matcher codeMatcher = codePattern.matcher(html);
        
        while (codeMatcher.find()) {
            String fullBlock = codeMatcher.group(0);
            String placeholder = '[[[[CODE_BLOCK_' + codeIndex + ']]]]';
            codeMap.put(placeholder, fullBlock);
            html = html.replace(fullBlock, placeholder);
            codeIndex++;
        }

        if (shouldLinkify) {
            html = linkifyUrls(html);
        }
        
        for (String placeholder : codeMap.keySet()) {
            html = html.replace(placeholder, codeMap.get(placeholder));
        }

        html = styleCodeBlocks(html);
        return html;
    }
    
    private static String linkifyUrls(String html) {
        if (String.isBlank(html)) return html;

        Map<String, String> tagMap = new Map<String, String>();
        Integer tagIndex = 0;
        Pattern tagPattern = Pattern.compile('(?s)<[^>]+>'); 
        Matcher tagMatcher = tagPattern.matcher(html);
        
        while (tagMatcher.find()) {
            String tag = tagMatcher.group();
            String placeholder = '[[[[HTML_TAG_' + tagIndex + ']]]]';
            tagMap.put(placeholder, tag);
            html = html.replace(tag, placeholder); 
            tagIndex++;
        }

        String tldList = 'com|org|net|edu|gov|mil|biz|info|io|co|uk|be|eu|de|fr|it|es|nl|ru|ch|se|no|dk|pl|cs|cz|gr|ie|hu|pt|ro|sk|fi|bg|hr|lt|lv|ee|ca|au|nz|us|in|jp|cn|kr|br|mx|za|il|ae';
        
        String urlRegex = '(?i)' + 
            '(' + 
                '(?:https?://|www\\.)[^\\s<"\\x5B\\x5D]+' +  
                '|' +
                '(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+(?:' + tldList + ')' + 
                '(?:/[\\w.,@?^=%&:/~+#-]*)?' + 
            ')';

        Pattern urlPattern = Pattern.compile(urlRegex);
        Matcher urlMatcher = urlPattern.matcher(html);
        
        String result = '';
        Integer lastEnd = 0;
        
        while (urlMatcher.find()) {
            result += html.substring(lastEnd, urlMatcher.start());
            String rawUrl = urlMatcher.group(1);
            String url = rawUrl;
            
            while (true) {
                Boolean trimmed = false;
                String lastChar = url.right(1);
                
                if (lastChar == '.' || lastChar == ',' || lastChar == '!' || lastChar == '?' || lastChar == ';' || lastChar == ':' || lastChar == ']') {
                    url = url.substring(0, url.length() - 1);
                    trimmed = true;
                }
                else if (lastChar == ')') {
                    Integer openCount = url.countMatches('(');
                    Integer closeCount = url.countMatches(')');
                    if (closeCount > openCount) {
                        url = url.substring(0, url.length() - 1);
                        trimmed = true;
                    }
                }
                if (!trimmed) break;
                if (url.length() == 0) break;
            }
            
            String trailingPunctuation = rawUrl.substring(url.length());
            
            if (url.length() < 4) {
                result += rawUrl;
                lastEnd = urlMatcher.end();
                continue;
            }

            String href = url;
            if (!url.startsWithIgnoreCase('http') && !url.startsWithIgnoreCase('ftp')) {
                href = 'https://' + url;
            }
            
            result += '<a href="' + href + '" target="_blank" rel="noopener noreferrer">' + url + '</a>' + trailingPunctuation;
            lastEnd = urlMatcher.end();
        }
        result += html.substring(lastEnd);
        
        for (String placeholder : tagMap.keySet()) {
            result = result.replace(placeholder, tagMap.get(placeholder));
        }
        
        return result;
    }
    
    private static String styleCodeBlocks(String html) {
        if (String.isBlank(html)) return html;
        Pattern p = Pattern.compile('(?is)<code>(.*?)</code>');
        Matcher m = p.matcher(html);
        
        String result = html;
        Integer blockId = 0;
        
        while (m.find()) {
            String codeContent = m.group(1);
            String fullMatch = m.group(0);
            
            String[] lines = codeContent.split('\n');
            String numberedCode = '';
            for (Integer i = 0; i < lines.size(); i++) {
                numberedCode += '<div class="code-line"><span class="line-num">' + (i + 1) + '</span><span class="line-content">' + lines[i] + '</span></div>';
            }
            
            String codeId = 'code-block-' + blockId;
            blockId++;
            
            String replacement = '<div class="code-wrapper">' + 
                '<textarea class="raw-code-storage" style="display:none;">' + codeContent + '</textarea>' +
                '<button class="copy-btn">Copy</button>' + 
                '<code id="' + codeId + '" class="numbered-code">' + numberedCode + '</code>' + 
                '</div>';
            
            result = result.replace(fullMatch, replacement);
        }
        return result;
    }
}