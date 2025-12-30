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
        @AuraEnabled public String attachmentsHtml; // Dedicated field for attachments
        @AuraEnabled public String emailTo; // Email To addresses
        @AuraEnabled public String emailCc; // Email CC addresses
        @AuraEnabled public String emailBcc; // Email BCC addresses
        @AuraEnabled public String emailFrom; // Email From address
        @AuraEnabled public String emailSubject; // Email Subject for info popover
        
        public String sortDir; // Not exposed to LWC, just for internal sorting

        public Integer compareTo(Object compareTo) {
            TimelineItem other = (TimelineItem) compareTo;
            // DESC: newer items first (larger dates = -1)
            // ASC: older items first (smaller dates = -1)
            if (this.sortDir == 'asc') {
                if (this.createdDate < other.createdDate) return -1;
                if (this.createdDate > other.createdDate) return 1;
            } else {
                if (this.createdDate < other.createdDate) return 1;
                if (this.createdDate > other.createdDate) return -1;
            }
            return 0;
        }
    }

    // --- CONFIGURATION WRAPPER ---
    public class TimelineConfig {
        @AuraEnabled public String configId { get; set; } 
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
        @AuraEnabled public Boolean showAttachmentsCollapsed { get; set; }
        @AuraEnabled public Boolean useToastForUpdates { get; set; }
        @AuraEnabled public Integer previewLines { get; set; }
        @AuraEnabled public String configName { get; set; }
        @AuraEnabled public Boolean newestFirst { get; set; }
        
        public TimelineConfig() {
            this.batchSize = 10;
            this.debugMode = false;
            this.showToast = false;
            this.pollingInterval = 15000;
            this.defaultEmail = true;
            this.defaultInternal = true;
            this.defaultPublic = true;
            this.defaultSystem = false;
            this.visibleCharLimit = 0; 
            this.expandByDefault = false;
            this.showAttachmentsCollapsed = true;
            this.useToastForUpdates = false;
            this.previewLines = 1;
            this.configName = 'CC-001';
            this.newestFirst = true; // Default to newest first (desc)
        }
    }

    @AuraEnabled
    public static TimelineConfig getTimelineConfig() {
        TimelineConfig configWrapper = new TimelineConfig();
        Id currentUserId = UserInfo.getUserId();
        Custom_Configuration__c dbConfig;
        
        try {
            List<Custom_Configuration__c> configs = [
                SELECT Id, Name, Batch_Size__c, Debug_Mode__c, Loading_Times_Toast__c, 
                       Polling_Interval__c, Show_Email_Default__c, 
                       Show_Internal_Default__c, Show_Public_Default__c, 
                       Show_Sytem_Default__c, Visible_Character_Limit__c,
                       Expand_by_default__c, Show_Attachments_Collapsed__c,
                       Toast_for_new_data__c, Collapsed_Preview_Lines__c,
                       Newest_First__c
                FROM Custom_Configuration__c 
                WHERE Active__c = true 
                AND OwnerId = :currentUserId 
                LIMIT 1
            ];
            
            if (!configs.isEmpty()) {
                dbConfig = configs[0];
            } else {
                dbConfig = new Custom_Configuration__c(
                    OwnerId = currentUserId,
                    Active__c = true,
                    Batch_Size__c = 10,
                    Polling_Interval__c = 15,
                    Visible_Character_Limit__c = 0,
                    Expand_by_default__c = false,
                    Show_Email_Default__c = true,
                    Show_Attachments_Collapsed__c = true,
                    Toast_for_new_data__c = false,
                    Show_Internal_Default__c = true,
                    Collapsed_Preview_Lines__c = 1,
                    Show_Public_Default__c = true,
                    Show_Sytem_Default__c = false,
                    Debug_Mode__c = false,
                    Loading_Times_Toast__c = false,
                    Newest_First__c = true
                );
                insert dbConfig;
                dbConfig = [SELECT Id, Name FROM Custom_Configuration__c WHERE Id = :dbConfig.Id];
            }
            
            if (dbConfig != null) {
                configWrapper.configId = dbConfig.Id;
                configWrapper.configName = dbConfig.Name;
                if (dbConfig.Batch_Size__c != null) configWrapper.batchSize = (Integer)dbConfig.Batch_Size__c;
                configWrapper.debugMode = dbConfig.Debug_Mode__c;
                configWrapper.showToast = dbConfig.Loading_Times_Toast__c;
                if (dbConfig.Polling_Interval__c != null) configWrapper.pollingInterval = (Integer)dbConfig.Polling_Interval__c * 1000; 
                configWrapper.defaultEmail = dbConfig.Show_Email_Default__c;
                configWrapper.defaultInternal = dbConfig.Show_Internal_Default__c;
                configWrapper.defaultPublic = dbConfig.Show_Public_Default__c;
                configWrapper.defaultSystem = dbConfig.Show_Sytem_Default__c;
                if (dbConfig.Visible_Character_Limit__c != null) configWrapper.visibleCharLimit = (Integer)dbConfig.Visible_Character_Limit__c;
                if (dbConfig.Collapsed_Preview_Lines__c != null) {
                    configWrapper.previewLines = (Integer)dbConfig.Collapsed_Preview_Lines__c;
                }
                configWrapper.expandByDefault = dbConfig.Expand_by_default__c;
                configWrapper.showAttachmentsCollapsed = dbConfig.Show_Attachments_Collapsed__c;
                configWrapper.useToastForUpdates = dbConfig.Toast_for_new_data__c;
                configWrapper.newestFirst = (dbConfig.Newest_First__c != null) ? dbConfig.Newest_First__c : true;
            }
        } catch (Exception e) {
            System.debug('Error in getTimelineConfig: ' + e.getMessage());
        }
        return configWrapper;
    }

    @AuraEnabled
    public static List<TimelineItem> getTimelineData(Id caseId, DateTime referenceDate, Integer limitSize, String sortDirection, Boolean debugMode) {
        if (limitSize == null || limitSize < 1) limitSize = 10;
        if (String.isBlank(sortDirection)) sortDirection = 'desc';
        if (debugMode == null) debugMode = false;
        
        // For DESC (newest first): use beforeDate logic (MessageDate < referenceDate)
        // For ASC (oldest first): use afterDate logic (MessageDate > referenceDate)
        DateTime queryDate = (referenceDate == null) ? 
            (sortDirection == 'desc' ? DateTime.now().addSeconds(1) : DateTime.newInstance(1900, 1, 1)) : 
            referenceDate;
        
        String emailOrder = (sortDirection == 'asc') ? 'ASC' : 'DESC';
        String feedOrder = (sortDirection == 'asc') ? 'ASC' : 'DESC';
        String operator = (sortDirection == 'asc') ? '>' : '<';

        String emailQuery = 'SELECT Id, Subject, HtmlBody, TextBody, MessageDate, FromName, FromAddress, ' +
                           'ToAddress, CcAddress, BccAddress, CreatedBy.Name, Incoming ' +
                           'FROM EmailMessage ' +
                           'WHERE ParentId = :caseId AND Status != \'5\' AND MessageDate ' + operator + ' :queryDate ' +
                           'ORDER BY MessageDate ' + emailOrder + ' LIMIT :limitSize';
        
        if (debugMode) {
            System.debug('Email Query: ' + emailQuery);
            System.debug('Query Date: ' + queryDate);
            System.debug('Sort Direction: ' + sortDirection);
        }

        List<EmailMessage> emailCandidates = Database.query(emailQuery);
        
        if (debugMode) {
            System.debug('Email candidates found: ' + emailCandidates.size());
        }

        String feedQuery = 'SELECT Id, Body, CreatedDate, CreatedBy.Name, Type, Visibility, Title, Status, IsRichText, ' +
                          '(SELECT FieldName, OldValue, NewValue FROM FeedTrackedChanges), ' +
                          '(SELECT Id, RecordId, Type, Title FROM FeedAttachments WHERE Type IN (\'InlineImage\', \'Content\')) ' +
                          'FROM FeedItem ' +
                          'WHERE ParentId = :caseId AND Type != \'EmailMessageEvent\' AND CreatedDate ' + operator + ' :queryDate ' +
                          'ORDER BY CreatedDate ' + feedOrder + ' LIMIT :limitSize';
        
        if (debugMode) {
            System.debug('Feed Query: ' + feedQuery);
        }

        List<FeedItem> feedCandidates = Database.query(feedQuery);
        
        if (debugMode) {
            System.debug('Feed candidates found: ' + feedCandidates.size());
        }

        List<SObject> combinedRaw = new List<SObject>();
        combinedRaw.addAll((List<SObject>)emailCandidates);
        combinedRaw.addAll((List<SObject>)feedCandidates);

        if (debugMode) {
            System.debug('Before merge - Email count: ' + emailCandidates.size() + ', Feed count: ' + feedCandidates.size());
            System.debug('Creating wrappers with sortDirection: ' + sortDirection);
        }

        List<RawItemWrapper> wrappers = new List<RawItemWrapper>();
        for(SObject obj : combinedRaw) {
            wrappers.add(new RawItemWrapper(obj, sortDirection));
        }
        wrappers.sort();
        
        if (debugMode && wrappers.size() > 0) {
            System.debug('After sort - First item date: ' + wrappers[0].sortDate + ', Last item date: ' + wrappers[wrappers.size()-1].sortDate);
        }

        List<EmailMessage> finalEmails = new List<EmailMessage>();
        List<FeedItem> finalFeeds = new List<FeedItem>();

        Integer count = 0;
        for(RawItemWrapper w : wrappers) {
            if (count >= limitSize) break;
            if (w.obj instanceof EmailMessage) finalEmails.add((EmailMessage)w.obj);
            else finalFeeds.add((FeedItem)w.obj);
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
                        if (res instanceof ConnectApi.FeedItem) connectMap.put(((ConnectApi.FeedItem)res).id, (ConnectApi.FeedItem)res);
                    }
                }
            } catch (Exception e) { System.debug('ConnectAPI Error: ' + e.getMessage()); }
        }

        return processItems(finalEmails, finalFeeds, connectMap, sortDirection);
    }

    public class RawItemWrapper implements Comparable {
        public SObject obj;
        public DateTime sortDate;
        public String sortDir;
        
        public RawItemWrapper(SObject o, String sortDirection) {
            this.obj = o;
            this.sortDir = (String.isBlank(sortDirection)) ? 'desc' : sortDirection;
            if (o instanceof EmailMessage) this.sortDate = ((EmailMessage)o).MessageDate;
            else this.sortDate = ((FeedItem)o).CreatedDate;
        }
        
        public Integer compareTo(Object compareTo) {
            RawItemWrapper other = (RawItemWrapper) compareTo;
            // DESC: newer items first (larger dates = -1)
            // ASC: older items first (smaller dates = -1)
            if (this.sortDir == 'asc') {
                if (this.sortDate < other.sortDate) return -1;
                if (this.sortDate > other.sortDate) return 1;
            } else {
                if (this.sortDate < other.sortDate) return 1;
                if (this.sortDate > other.sortDate) return -1;
            }
            return 0;
        }
    }

    @TestVisible 
    private static List<TimelineItem> processItems(List<EmailMessage> emails, List<FeedItem> feedItems, Map<Id, ConnectApi.FeedItem> connectMap, String sortDirection) {
        List<TimelineItem> combinedList = new List<TimelineItem>();
        Map<String, String> statusMap = getStatusMap();
        String baseUrl = getBaseUrl();
        String fileBaseUrl = getFileBaseUrl();
        
        // NEW: Collect all email addresses from emails to lookup Salesforce records
        Set<String> allEmailAddresses = new Set<String>();
        for (EmailMessage em : emails) {
            if (String.isNotBlank(em.ToAddress)) {
                allEmailAddresses.addAll(extractEmailAddresses(em.ToAddress));
            }
            if (String.isNotBlank(em.CcAddress)) {
                allEmailAddresses.addAll(extractEmailAddresses(em.CcAddress));
            }
            if (String.isNotBlank(em.BccAddress)) {
                allEmailAddresses.addAll(extractEmailAddresses(em.BccAddress));
            }
            if (String.isNotBlank(em.FromAddress)) {
                allEmailAddresses.addAll(extractEmailAddresses(em.FromAddress));
            }
        }
        
        // Build email-to-record map
        Map<String, EmailRecordMatch> emailToRecordMap = buildEmailToRecordMap(allEmailAddresses);
        
        Map<String, String> documentIdToVersionId = new Map<String, String>();
        Map<String, String> versionIdToDocumentId = new Map<String, String>();
        Map<String, String> docIdToTitle = new Map<String, String>();
        Map<String, String> docIdToExtension = new Map<String, String>();
        
        Set<String> contentDocIds = new Set<String>();
        Set<String> contentVersionIds = new Set<String>();

        for (FeedItem cf : feedItems) {
            if (cf.FeedAttachments != null && !cf.FeedAttachments.isEmpty()) {
                for (FeedAttachment fa : cf.FeedAttachments) {
                    String rId = (String)fa.RecordId;
                    if ((fa.Type == 'InlineImage' || fa.Type == 'Content') && String.isNotBlank(rId)) {
                        if (rId.startsWith('069')) contentDocIds.add(rId);
                        else if (rId.startsWith('068')) contentVersionIds.add(rId);
                    }
                }
            }
        }

        if (!contentDocIds.isEmpty() || !contentVersionIds.isEmpty()) {
            try {
                List<ContentVersion> versions = [SELECT Id, ContentDocumentId, Title, FileExtension
                                                FROM ContentVersion 
                                                WHERE (ContentDocumentId IN :contentDocIds OR Id IN :contentVersionIds)
                                                AND IsLatest = true];
                for (ContentVersion cv : versions) {
                    documentIdToVersionId.put(cv.ContentDocumentId, cv.Id);
                    versionIdToDocumentId.put(cv.Id, cv.ContentDocumentId);
                    docIdToTitle.put(cv.ContentDocumentId, cv.Title); docIdToExtension.put(cv.ContentDocumentId, cv.FileExtension);
                    docIdToTitle.put(cv.Id, cv.Title); docIdToExtension.put(cv.Id, cv.FileExtension);
                }
            } catch (Exception e) { System.debug('ERROR querying ContentVersion: ' + e.getMessage()); }
        }

        // --- PROCESS EMAILS ---
        Set<Id> emailIds = new Set<Id>();
        for (EmailMessage em : emails) emailIds.add(em.Id);
        
        Map<Id, List<ContentDocumentLink>> emailAttachments = new Map<Id, List<ContentDocumentLink>>();
        if (!emailIds.isEmpty()) {
            for (ContentDocumentLink link : [SELECT Id, ContentDocumentId, LinkedEntityId, ContentDocument.Title, ContentDocument.FileExtension
                                             FROM ContentDocumentLink 
                                             WHERE LinkedEntityId IN :emailIds]) {
                if (!emailAttachments.containsKey(link.LinkedEntityId)) emailAttachments.put(link.LinkedEntityId, new List<ContentDocumentLink>());
                emailAttachments.get(link.LinkedEntityId).add(link);
            }
        }
        Map<Id, List<Attachment>> emailLegacyAttachments = new Map<Id, List<Attachment>>();
        if (!emailIds.isEmpty()) {
            // Query legacy Attachment object
            for (Attachment att : [SELECT Id, Name, ParentId, ContentType FROM Attachment WHERE ParentId IN :emailIds]) {
                if (!emailLegacyAttachments.containsKey(att.ParentId)) {
                    emailLegacyAttachments.put(att.ParentId, new List<Attachment>());
                }
                emailLegacyAttachments.get(att.ParentId).add(att);
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
            item.sortDir = sortDirection;
            
            // Populate email recipient fields with Salesforce record links
            item.emailTo = enrichEmailAddresses(em.ToAddress, emailToRecordMap);
            item.emailCc = enrichEmailAddresses(em.CcAddress, emailToRecordMap);
            item.emailBcc = enrichEmailAddresses(em.BccAddress, emailToRecordMap);
            item.emailFrom = enrichEmailAddresses(
                String.isNotBlank(em.FromAddress) ? em.FromAddress : em.FromName, 
                emailToRecordMap
            );
            item.emailSubject = em.Subject;

            if (String.isNotBlank(em.HtmlBody)) item.body = em.HtmlBody; 
            else item.body = (em.TextBody != null) ? em.TextBody.replace('\n', '<br/>') : '';
            
            item.hasHistory = false; item.historyBody = ''; 
            item.attachmentsHtml = ''; // Initialize
            List<String> attachmentCards = new List<String>();
            if (emailAttachments.containsKey(em.Id)) {
                for (ContentDocumentLink link : emailAttachments.get(em.Id)) {
                    attachmentCards.add(getAttachmentCardHtml(link.ContentDocumentId, link.ContentDocument.Title, link.ContentDocument.FileExtension));
                }
            }

            // B. Add Legacy Attachments
            if (emailLegacyAttachments.containsKey(em.Id)) {
                for (Attachment att : emailLegacyAttachments.get(em.Id)) {
                    // Extract extension from name (e.g. "invoice.pdf" -> "pdf")
                    String ext = '';
                    if (att.Name != null && att.Name.contains('.')) {
                        ext = att.Name.substringAfterLast('.');
                    }
                    attachmentCards.add(getAttachmentCardHtml(att.Id, att.Name, ext));
                }
            }
            
            // Check if ANY attachments exist (File or Legacy)
            if (!attachmentCards.isEmpty()) {
                item.attachmentsHtml = '<div style="margin-top:10px; padding-top:6px; border-top:1px solid #e5e5e5;">' + String.join(attachmentCards, '') + '</div>';
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
            item.attachmentsHtml = ''; // Initialize
            item.sortDir = sortDirection;

            ConnectApi.FeedItem connectFeedItem = (connectMap != null) ? connectMap.get(soqlFeedItem.Id) : null;

            if (connectFeedItem != null && connectFeedItem.actor != null) item.author = connectFeedItem.actor.name;
            else item.author = (soqlFeedItem.CreatedBy != null) ? soqlFeedItem.CreatedBy.Name : 'System';

            Boolean isSystemType = (soqlFeedItem.Type == 'TrackedChange' || soqlFeedItem.Type == 'CreateRecordEvent' || soqlFeedItem.Type == 'ActivityEvent' || soqlFeedItem.Type == 'CaseCommentPost' || soqlFeedItem.Type == 'ChangeStatusPost' || (soqlFeedItem.CreatedBy != null && soqlFeedItem.CreatedBy.Name == 'Automated Process') || soqlFeedItem.Title == 'SYSTEM' || soqlFeedItem.Title == 'MILESTONE' || soqlFeedItem.Title == 'Owner Changed');

            if (isSystemType) {
                item.category = 'System'; item.isInternal = true; 
                item.title = (soqlFeedItem.Title == 'SYSTEM' || soqlFeedItem.Title == 'MILESTONE' || soqlFeedItem.Title == 'Owner Changed') ? '⚙️ ' + soqlFeedItem.Title : '⚙️ ' + formatSystemTitle(soqlFeedItem.Type);
            } else if (soqlFeedItem.Visibility == 'AllUsers') {
                item.category = 'Public'; item.isInternal = false; item.title = '💬 Public Post';
            } else {
                item.category = 'Internal'; item.isInternal = true; item.title = '🔒 Internal Note';
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
                            String mentionLink = '<a href="/' + m.record.id + '" class="mention-link" data-record-id="' + m.record.id + '" style="color:#0176d3; font-weight:bold; text-decoration:none;">' + m.text + '</a>';
                            String placeholder = '[[[[MENTION_' + mentionIndex + ']]]]';
                            mentionProtectionMap.put(placeholder, mentionLink); mentionReplacements.put(m.text, placeholder); mentionIndex++;
                        }
                    }
                }
                for (String mentionText : mentionReplacements.keySet()) formattedBody = formattedBody.replace(mentionText, mentionReplacements.get(mentionText));
                
                String cleanBody = fixRelativeImageUrls(formattedBody, baseUrl, fileBaseUrl, documentIdToVersionId);
                
                // CHANGED: Use new helper to get attachments separately
                item.attachmentsHtml = getFeedAttachmentsHtml(soqlFeedItem, versionIdToDocumentId, docIdToTitle, docIdToExtension);

                String parsedResult = null;
                if (String.isNotBlank(formattedBody) && (formattedBody.containsIgnoreCase('feedEvent') || formattedBody.contains('{"fu"'))) parsedResult = parseFeedEventString(formattedBody, statusMap);

                if (parsedResult != null) item.body = parsedResult;
                else if (String.isNotBlank(cleanBody)) {
                    item.body = cleanHtml(cleanBody, true);
                    item.body = makeImagesClickable(item.body, versionIdToDocumentId);
                    for (String placeholder : mentionProtectionMap.keySet()) item.body = item.body.replace(placeholder, mentionProtectionMap.get(placeholder));
                } else item.body = '<i>[' + soqlFeedItem.Type + ']</i>';
            } 
            else {
                String formattedBody = soqlFeedItem.Body != null ? soqlFeedItem.Body : '';
                String cleanBody = fixRelativeImageUrls(formattedBody, baseUrl, fileBaseUrl, documentIdToVersionId);
                
                // CHANGED: Use new helper to get attachments separately
                item.attachmentsHtml = getFeedAttachmentsHtml(soqlFeedItem, versionIdToDocumentId, docIdToTitle, docIdToExtension);

                String parsedResult = null;
                if (String.isNotBlank(formattedBody) && (formattedBody.containsIgnoreCase('feedEvent') || formattedBody.contains('{"fu"'))) parsedResult = parseFeedEventString(formattedBody, statusMap);

                if (parsedResult != null) item.body = parsedResult;
                else if (soqlFeedItem.FeedTrackedChanges != null && !soqlFeedItem.FeedTrackedChanges.isEmpty() && String.isBlank(formattedBody)) item.body = processTrackedChanges(soqlFeedItem.FeedTrackedChanges, statusMap);
                else if (String.isNotBlank(cleanBody)) {
                    item.body = cleanHtml(cleanBody, true); item.body = makeImagesClickable(item.body, versionIdToDocumentId);
                } else item.body = '<i>[' + soqlFeedItem.Type + ']</i>';
            }

            combinedList.add(item);
        }

        combinedList.sort();
        return combinedList;
    }

    private static String getAttachmentCardHtml(String docId, String fileName, String fileExtension) {
        if (fileName == null) fileName = 'Attachment';
        
        String fileIcon = '📄'; 
        String checkStr = (String.isNotBlank(fileExtension)) ? '.' + fileExtension.toLowerCase() : fileName.toLowerCase();
        
        if (checkStr.endsWith('png') || checkStr.endsWith('jpg') || checkStr.endsWith('jpeg') || checkStr.endsWith('gif') || checkStr.endsWith('webp')) fileIcon = '🖼️';
        else if (checkStr.endsWith('pdf')) fileIcon = '📕';
        else if (checkStr.endsWith('doc') || checkStr.endsWith('docx')) fileIcon = '📘';
        else if (checkStr.endsWith('xls') || checkStr.endsWith('xlsx') || checkStr.endsWith('csv')) fileIcon = '📊';
        else if (checkStr.endsWith('ppt') || checkStr.endsWith('pptx')) fileIcon = '📙';
        else if (checkStr.endsWith('txt')) fileIcon = '📝';
        else if (checkStr.endsWith('zip') || checkStr.endsWith('rar') || checkStr.endsWith('7z')) fileIcon = '📦';
        
        // Determine correct object name for the URL based on ID prefix
        String objectName = 'ContentDocument';
        if (docId != null && docId.startsWith('00P')) {
            objectName = 'Attachment';
        }

        return '<a href="/lightning/r/' + objectName + '/' + docId + '/view" class="image-preview-link" data-doc-id="' + docId + '" style="display:inline-flex; align-items:center; margin:4px 8px 4px 0; padding:6px 10px; background:#f3f2f2; border:1px solid #c9c7c5; border-radius:3px; text-decoration:none; color:#0176d3; font-size:0.8125rem; cursor:pointer;">' +
            '<span style="margin-right:6px; font-size:1.1em;">' + fileIcon + '</span>' + fileName +
            '</a>';
    }

    // --- REPLACED: New helper that returns the attachment HTML string instead of modifying the body ---
    private static String getFeedAttachmentsHtml(FeedItem soqlFeedItem, Map<String, String> versionIdToDocumentId, Map<String, String> docIdToTitle, Map<String, String> docIdToExtension) {
        List<String> attachmentCards = new List<String>();
        
        if (soqlFeedItem.FeedAttachments != null && !soqlFeedItem.FeedAttachments.isEmpty()) {
            for (FeedAttachment fa : soqlFeedItem.FeedAttachments) {
                String rId = (String)fa.RecordId;
                if ((fa.Type == 'Content' || fa.Type == 'InlineImage') && String.isNotBlank(rId)) {
                    String docId = null;
                    
                    if (rId.startsWith('069')) docId = rId;
                    else if (rId.startsWith('068') && versionIdToDocumentId.containsKey(rId)) docId = versionIdToDocumentId.get(rId);

                    if (String.isNotBlank(docId)) {
                        String realTitle = docIdToTitle.get(docId);
                        String realExt = docIdToExtension.get(docId);
                        if (String.isBlank(realTitle)) realTitle = fa.Title;
                        attachmentCards.add(getAttachmentCardHtml(docId, realTitle, realExt));
                    }
                }
            }
        }

        if (!attachmentCards.isEmpty()) {
            return '<div style="margin-top:10px; padding-top:6px; border-top:1px solid #e5e5e5;">' + String.join(attachmentCards, '') + '</div>';
        }
        return '';
    }

    @AuraEnabled
    public static Boolean checkForNewItems(Id caseId, DateTime lastCheckDate) {
        if (caseId == null || lastCheckDate == null) return false;
        Integer count = [SELECT Count() FROM FeedItem WHERE ParentId = :caseId AND CreatedDate > :lastCheckDate AND Type IN ('TextPost', 'EmailMessageEvent', 'ContentPost', 'LinkPost') LIMIT 1];
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
                } catch (Exception e) { result.add('<b>' + label + '</b>: <i>(Updated)</i>'); }
            } else {
                if ((field == 'Status' || field == 'Case.Status') && statusMap != null) {
                    if (oldV != null && statusMap.containsKey(oldV)) oldV = statusMap.get(oldV);
                    if (newV != null && statusMap.containsKey(newV)) newV = statusMap.get(newV);
                }
                if (oldV == null || oldV == 'null') oldV = '(blank)';
                if (newV == null || newV == 'null') newV = '(blank)';
                if (oldV == '(blank)' && newV == '(blank)') result.add('<b>' + label + '</b>: <i>(Updated)</i>');
                else result.add('<b>' + label + '</b>: ' + oldV + ' &rarr; ' + newV);
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
            String fullMatch = m0.group(); String beforeSrc = m0.group(1); String contentDocumentId = m0.group(2);
            String contentVersionId = documentIdToVersionId.get(contentDocumentId);
            String replacement = (String.isNotBlank(contentVersionId)) ? '<img' + beforeSrc + 'src="' + fileBaseUrl + '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + contentVersionId + '&operationContext=CHATTER&contentId=' + contentDocumentId + '"' : fullMatch;
            result = result.replace(fullMatch, replacement);
        }
        if (String.isNotBlank(baseUrl)) {
            Pattern p1 = Pattern.compile('(?i)<img([^>]*?)src="(/sfc/[^"]+)"');
            Matcher m1 = p1.matcher(result);
            while (m1.find()) {
                String fullMatch = m1.group(); String relativeUrl = m1.group(2);
                result = result.replace(fullMatch, '<img' + m1.group(1) + 'src="' + baseUrl + relativeUrl + '"');
            }
        }
        return result;
    }

    @TestVisible private static String getFileBaseUrl() {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        if (baseUrl.contains('.my.salesforce.com')) baseUrl = baseUrl.replace('.my.salesforce.com', '.file.force.com');
        else if (baseUrl.contains('.lightning.force.com')) baseUrl = baseUrl.replace('.lightning.force.com', '.file.force.com');
        if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        return baseUrl;
    }
    @TestVisible private static String getBaseUrl() {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        return baseUrl;
    }

    @TestVisible
    private static String parseFeedEventString(String cleanBody, Map<String, String> statusMap) {
        try {
            Integer idxStart = cleanBody.indexOf('{'); Integer idxEnd = cleanBody.lastIndexOf('}');
            if (idxStart == -1 || idxEnd == -1 || idxEnd <= idxStart) return null;
            String jsonPart = cleanBody.substring(idxStart, idxEnd + 1).replace('"', '"').replace('"', '"'); 
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonPart);
            if (root.containsKey('fu')) {
                List<Object> fieldUpdates = (List<Object>) root.get('fu');
                for (Object itemObj : fieldUpdates) {
                    Map<String, Object> updateMap = (Map<String, Object>) itemObj;
                    String field = String.valueOf(updateMap.get('fn')); 
                    String oldV = String.valueOf(updateMap.get('ov')); String newV = String.valueOf(updateMap.get('nv')); 
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

    @TestVisible private static Map<String, String> getStatusMap() {
        Map<String, String> m = new Map<String, String>(); m.put('1', 'New'); m.put('2', 'On Hold'); m.put('3', 'Closed'); m.put('6', 'Open'); m.put('7', 'Working'); m.put('8', 'Waiting for Customer'); m.put('9', 'Solved');
        try { for(Schema.PicklistEntry f : Case.Status.getDescribe().getPicklistValues()) { m.put(f.getValue(), f.getLabel()); m.put(f.getLabel(), f.getLabel()); } } catch (Exception e) { }
        return m;
    }
    @TestVisible private static String formatSystemTitle(String type) { if (type == 'TrackedChange') return 'Field Update'; if (type == 'ChangeStatusPost') return 'Status Changed'; if (type == 'CreateRecordEvent') return 'Record Created'; return type; }
    
    @TestVisible private static String makeImagesClickable(String html, Map<String, String> versionIdToDocId) {
        if (String.isBlank(html)) return html;
        String result = html;
        Pattern imgPattern = Pattern.compile('(?i)<img([^>]*?)src="([^"]+)"([^>]*?)>');
        Matcher imgMatcher = imgPattern.matcher(result);
        while (imgMatcher.find()) {
            String fullMatch = imgMatcher.group(); String beforeSrc = imgMatcher.group(1); String srcUrl = imgMatcher.group(2); String afterSrc = imgMatcher.group(3);
            String versionId = null;
            if (srcUrl.contains('versionId=')) {
                Integer startIdx = srcUrl.indexOf('versionId=') + 10; Integer endIdx = srcUrl.indexOf('&', startIdx);
                if (endIdx == -1) endIdx = srcUrl.length(); versionId = srcUrl.substring(startIdx, endIdx);
            }
            String docId = versionIdToDocId.get(versionId);
            String replacement = (String.isNotBlank(docId)) ? '<a href="/lightning/r/ContentDocument/' + docId + '/view" class="image-preview-link" data-doc-id="' + docId + '" style="display:block; max-width:80%;"><img' + beforeSrc + 'src="' + srcUrl + '"' + afterSrc + ' style="max-width:100%; cursor:pointer;"></a>' : '<a href="' + srcUrl.replaceAll('([?&])rendition=[^&]*(&|$)', '$1').replaceAll('[?&]$', '') + '" target="_blank" style="display:block; max-width:80%;"><img' + beforeSrc + 'src="' + srcUrl + '"' + afterSrc + ' style="max-width:100%; cursor:pointer;"></a>';
            result = result.replace(fullMatch, replacement);
        }
        return result;
    }

    private static String cleanHtml(String html, Boolean shouldLinkify) {
        if (String.isBlank(html)) return '';
        html = html.replace('<html', '<div').replace('</html>', '</div>').replace('<body', '<div').replace('</body>', '</div>').replace('<!DOCTYPE html>', '');
        Map<String, String> codeMap = new Map<String, String>(); Integer codeIndex = 0;
        Pattern codePattern = Pattern.compile('(?is)<code>(.*?)</code>'); Matcher codeMatcher = codePattern.matcher(html);
        while (codeMatcher.find()) { String fullBlock = codeMatcher.group(0); String placeholder = '[[[[CODE_BLOCK_' + codeIndex + ']]]]'; codeMap.put(placeholder, fullBlock); html = html.replace(fullBlock, placeholder); codeIndex++; }
        if (shouldLinkify) html = linkifyUrls(html);
        for (String placeholder : codeMap.keySet()) html = html.replace(placeholder, codeMap.get(placeholder));
        return styleCodeBlocks(html);
    }
    
    private static String linkifyUrls(String html) {
        if (String.isBlank(html)) return html;
        Map<String, String> tagMap = new Map<String, String>(); Integer tagIndex = 0;
        Pattern tagPattern = Pattern.compile('(?s)<[^>]+>'); Matcher tagMatcher = tagPattern.matcher(html);
        while (tagMatcher.find()) { String tag = tagMatcher.group(); String placeholder = '[[[[HTML_TAG_' + tagIndex + ']]]]'; tagMap.put(placeholder, tag); html = html.replace(tag, placeholder); tagIndex++; }
        String tldList = 'com|org|net|edu|gov|mil|biz|info|io|co|uk|be|eu|de|fr|it|es|nl|ru|ch|se|no|dk|pl|cs|cz|gr|ie|hu|pt|ro|sk|fi|bg|hr|lt|lv|ee|ca|au|nz|us|in|jp|cn|kr|br|mx|za|il|ae';
        Pattern urlPattern = Pattern.compile('(?i)((?:https?://|www\\.)[^\\s<"\\x5B\\x5D]+|(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+(?:' + tldList + ')(?:/[\\w.,@?^=%&:/~+#-]*)?)');
        Matcher urlMatcher = urlPattern.matcher(html);
        String result = ''; Integer lastEnd = 0;
        while (urlMatcher.find()) {
            result += html.substring(lastEnd, urlMatcher.start()); String rawUrl = urlMatcher.group(1); String url = rawUrl;
            while (true) {
                Boolean trimmed = false; String lastChar = url.right(1);
                if (lastChar == '.' || lastChar == ',' || lastChar == '!' || lastChar == '?' || lastChar == ';' || lastChar == ':' || lastChar == ']') { url = url.substring(0, url.length() - 1); trimmed = true; }
                else if (lastChar == ')') { if (url.countMatches(')') > url.countMatches('(')) { url = url.substring(0, url.length() - 1); trimmed = true; } }
                if (!trimmed || url.length() == 0) break;
            }
            String trailingPunctuation = rawUrl.substring(url.length());
            if (url.length() < 4) { result += rawUrl; lastEnd = urlMatcher.end(); continue; }
            String href = (url.startsWithIgnoreCase('http') || url.startsWithIgnoreCase('ftp')) ? url : 'https://' + url;
            result += '<a href="' + href + '" target="_blank" rel="noopener noreferrer">' + url + '</a>' + trailingPunctuation;
            lastEnd = urlMatcher.end();
        }
        result += html.substring(lastEnd);
        for (String placeholder : tagMap.keySet()) result = result.replace(placeholder, tagMap.get(placeholder));
        return result;
    }
    
    private static String styleCodeBlocks(String html) {
        if (String.isBlank(html)) return html;
        
        Pattern p = Pattern.compile('(?is)<code>(.*?)</code>'); 
        Matcher m = p.matcher(html);
        String result = html; 
        Integer blockId = 0;
        
        while (m.find()) {
            String originalCode = m.group(1); 
            String fullMatch = m.group(0);

            if (originalCode.length() > 30000) {
                 result = result.replace(fullMatch, '<div class="code-wrapper"><textarea class="raw-code-storage" style="display:none;">' + originalCode + '</textarea><button class="copy-btn">Copy</button><code id="code-block-' + (blockId++) + '" class="numbered-code"><div class="code-line"><i>(Code block too large)</i></div></code></div>');
                 continue; 
            }
            
            // 1. ESCAPE HTML
            String styledCode = originalCode.replace('<', '&lt;').replace('>', '&gt;');
            
            // --- STEP 2: EXTRACT COMMENTS ---
            // We use a specific pattern for block comments that MUST have a closing */
            // We use a separate pattern for line comments
            Map<String, String> commentMap = new Map<String, String>();
            Integer commentIdx = 0;

            // 2A. Block Comments /* ... */
            // (?s) enables dot-matches-newline for this pattern
            Pattern blockCommentPat = Pattern.compile('(?s)/\\*.*?\\*/');
            Matcher blockMatcher = blockCommentPat.matcher(styledCode);
            while (blockMatcher.find()) {
                String match = blockMatcher.group();
                String token = '###BLOCK_COMMENT_' + commentIdx + '###';
                commentMap.put(token, match);
                // We replace FIRST occurrence to avoid messing up identical comments
                styledCode = styledCode.replaceFirst(Pattern.quote(match), token); 
                commentIdx++;
            }

            // 2B. Line Comments // ...
            // (?m) ensures ^ and $ match start/end of lines
            Pattern lineCommentPat = Pattern.compile('(?m)//.*$');
            Matcher lineMatcher = lineCommentPat.matcher(styledCode);
            while (lineMatcher.find()) {
                String match = lineMatcher.group();
                String token = '###LINE_COMMENT_' + commentIdx + '###';
                commentMap.put(token, match);
                styledCode = styledCode.replaceFirst(Pattern.quote(match), token);
                commentIdx++;
            }

            // --- STEP 3: MARK TAGS (Layer 1 - Blue) ---
            styledCode = styledCode.replaceAll('(&lt;.*?&gt;)', '###TAG_START###$1###TAG_END###');

            // --- STEP 4: HIGHLIGHT QUOTES (Layer 2 - Green #529766) ---
// Matches: "..."  '...'  &quot;...&quot;  &#34;...&#34;  &#39;...&#39;  &apos;...&apos;
// Also handles escaped quotes inside real strings.
styledCode = styledCode.replaceAll(
    '(?s)(&quot;.*?&quot;|&#34;.*?&#34;|&apos;.*?&apos;|&#39;.*?&#39;|"(?:\\\\.|[^"\\\\])*"|\'(?:\\\\.|[^\'\\\\])*\')',
    '<span style="color:#529766;">$1</span>'
);
            // --- STEP 5: HIGHLIGHT HEX CODES (Layer 3 - Red #BB0417) ---
            // Matches #123456 or #123456;
            // Negative lookbehind (?<!color:) prevents breaking the span we just added
            styledCode = styledCode.replaceAll('(?<!color:)#[A-Fa-f0-9]{6};?', '<span style="color:#BB0417;">$0</span>');

            // --- STEP 6: RESTORE TAGS (Apply Blue #0C5CAC) ---
            styledCode = styledCode.replace('###TAG_START###', '<span style="color:#0C5CAC;">').replace('###TAG_END###', '</span>');

            // --- STEP 7: RESTORE COMMENTS (Apply Red #BB0417) ---
            // Restore Block comments
            for (String token : commentMap.keySet()) {
                if (token.contains('BLOCK_COMMENT')) {
                     styledCode = styledCode.replace(token, '<span style="color:#BB0417;">' + commentMap.get(token) + '</span>');
                }
            }
            // Restore Line comments
            for (String token : commentMap.keySet()) {
                if (token.contains('LINE_COMMENT')) {
                     styledCode = styledCode.replace(token, '<span style="color:#BB0417;">' + commentMap.get(token) + '</span>');
                }
            }

            // Final: Build Numbered Lines
            List<String> lines = styledCode.split('\n'); 
            String numberedCode = '';
            for (Integer i = 0; i < lines.size(); i++) {
                numberedCode += '<div class="code-line"><span class="line-num">' + (i + 1) + '</span><span class="line-content">' + lines[i] + '</span></div>';
            }
            
            result = result.replace(fullMatch, '<div class="code-wrapper"><textarea class="raw-code-storage" style="display:none;">' + originalCode + '</textarea><button class="copy-btn">Copy</button><code id="code-block-' + (blockId++) + '" class="numbered-code">' + numberedCode + '</code></div>');
        }
        return result;
    }
    
    // --- EMAIL ENRICHMENT METHODS ---
    
    // Wrapper class to hold email-to-record matches
    public class EmailRecordMatch {
        public String recordId;
        public String recordName;
        public String recordType; // 'User', 'Contact', or 'Lead'
        
        public EmailRecordMatch(String recordId, String recordName, String recordType) {
            this.recordId = recordId;
            this.recordName = recordName;
            this.recordType = recordType;
        }
    }
    
    // Extract individual email addresses from a comma-separated string
    private static Set<String> extractEmailAddresses(String emailString) {
        Set<String> emails = new Set<String>();
        if (String.isBlank(emailString)) return emails;
        
        // Split by comma or semicolon
        List<String> parts = emailString.split('[,;]');
        for (String part : parts) {
            String trimmed = part.trim();
            if (String.isNotBlank(trimmed)) {
                // Extract email from "Name <email@domain.com>" format
                Pattern p = Pattern.compile('<([^>]+)>');
                Matcher m = p.matcher(trimmed);
                if (m.find()) {
                    emails.add(m.group(1).toLowerCase());
                } else {
                    emails.add(trimmed.toLowerCase());
                }
            }
        }
        return emails;
    }
    
    // Build a map of email addresses to Salesforce records
    private static Map<String, EmailRecordMatch> buildEmailToRecordMap(Set<String> emailAddresses) {
        Map<String, EmailRecordMatch> emailMap = new Map<String, EmailRecordMatch>();
        if (emailAddresses.isEmpty()) return emailMap;
        
        // Query Contacts FIRST (highest priority)
        try {
            for (Contact c : [SELECT Id, Name, Email FROM Contact WHERE Email IN :emailAddresses]) {
                if (String.isNotBlank(c.Email)) {
                    emailMap.put(c.Email.toLowerCase(), new EmailRecordMatch(c.Id, c.Name, 'Contact'));
                }
            }
        } catch (Exception e) {
            System.debug('Error querying Contacts: ' + e.getMessage());
        }
        
        // Query Users SECOND (only if not already found as Contact)
        Set<String> remainingEmails = new Set<String>();
        for (String email : emailAddresses) {
            if (!emailMap.containsKey(email)) {
                remainingEmails.add(email);
            }
        }
        
        if (!remainingEmails.isEmpty()) {
            try {
                for (User u : [SELECT Id, Name, Email FROM User WHERE Email IN :remainingEmails AND IsActive = true]) {
                    if (String.isNotBlank(u.Email) && !emailMap.containsKey(u.Email.toLowerCase())) {
                        emailMap.put(u.Email.toLowerCase(), new EmailRecordMatch(u.Id, u.Name, 'User'));
                    }
                }
            } catch (Exception e) {
                System.debug('Error querying Users: ' + e.getMessage());
            }
        }
        
        return emailMap;
    }
    
    // Convert comma-separated email string to HTML with record links
    private static String enrichEmailAddresses(String emailString, Map<String, EmailRecordMatch> emailMap) {
        if (String.isBlank(emailString)) return '';
        
        List<String> enrichedParts = new List<String>();
        List<String> parts = emailString.split('[,;]');
        
        for (String part : parts) {
            String trimmed = part.trim();
            if (String.isBlank(trimmed)) continue;
            
            String displayName = trimmed;
            String emailAddr = trimmed;
            
            // Parse "Name <email@domain.com>" format
            Pattern p = Pattern.compile('(.+?)<([^>]+)>');
            Matcher m = p.matcher(trimmed);
            if (m.find()) {
                displayName = m.group(1).trim();
                emailAddr = m.group(2).trim();
            }
            
            String lookupEmail = emailAddr.toLowerCase();
            
            if (emailMap.containsKey(lookupEmail)) {
                EmailRecordMatch match = emailMap.get(lookupEmail);
                // Create clickable link with data attribute for navigation
                enrichedParts.add(
                    '<a href="/' + match.recordId + '" ' +
                    'class="email-recipient-link" ' +
                    'data-record-id="' + match.recordId + '" ' +
                    'style="color:#0176d3; text-decoration:none;">' +
                    (displayName.contains('@') ? match.recordName : displayName) +
                    '</a>'
                );
            } else {
                // No match found, just display the text
                enrichedParts.add(trimmed);
            }
        }
        
        return String.join(enrichedParts, ', ');
    }
}