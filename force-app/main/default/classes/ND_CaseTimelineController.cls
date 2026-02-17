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
        @AuraEnabled public List<CommentItem> comments; // Comments on the feed item or email
        @AuraEnabled public String feedItemId; // The ID of the FeedItem to post comments to
        
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
    
    @AuraEnabled
    public static void addComment(Id feedItemId, String commentBody) {
        if (String.isBlank(feedItemId) || String.isBlank(commentBody)) return;
        insert new FeedComment(FeedItemId = feedItemId, CommentBody = commentBody);
    }
    
    public class CommentItem {
        @AuraEnabled public String id;
        @AuraEnabled public String body;
        @AuraEnabled public String author;
        @AuraEnabled public DateTime createdDate;
        
        public CommentItem(String id, String body, String author, DateTime createdDate) {
            this.id = id;
            this.body = body;
            this.author = author;
            this.createdDate = createdDate;
        }
    }

    public class TimelineCounts {
        @AuraEnabled public Integer emailCount { get; set; }
        @AuraEnabled public Integer internalCount { get; set; }
        @AuraEnabled public Integer publicCount { get; set; }
        @AuraEnabled public Integer systemCount { get; set; }
        
        public TimelineCounts() {
            this.emailCount = 0;
            this.internalCount = 0;
            this.publicCount = 0;
            this.systemCount = 0;
        }
    }

    @AuraEnabled
    public static TimelineCounts getTimelineCounts(Id caseId) {
        TimelineCounts counts = new TimelineCounts();
        if (caseId == null) return counts;
        
        // 1. Email Count
        try {
            counts.emailCount = [SELECT Count() FROM EmailMessage WHERE ParentId = :caseId AND Status != '5'];
        } catch (Exception e) { System.debug('Error counting emails: ' + e.getMessage()); }
        
        // 2. Feed Items Count
        // Note: FeedItem has severe SOQL restrictions (no 'Type NOT IN', no 'CreatedBy.Name' filter, no aggregates on some fields).
        // Best approach is to fetch raw metadata (Limit 10000 for safety) and count in memory.
        try {
            List<String> systemTypes = new List<String>{'TrackedChange', 'CreateRecordEvent', 'ActivityEvent', 'CaseCommentPost', 'ChangeStatusPost', 'MilestoneEvent'};
            Set<String> sysTypeSet = new Set<String>(systemTypes);
            
            List<FeedItem> feeds = [SELECT Type, Visibility, CreatedBy.Name, Title 
                                    FROM FeedItem 
                                    WHERE ParentId = :caseId 
                                    AND Type != 'EmailMessageEvent' 
                                    LIMIT 10000];
            
            for (FeedItem fi : feeds) {
                Boolean isSystem = false;
                if (sysTypeSet.contains(fi.Type) || fi.CreatedBy.Name == 'Automated Process') {
                    isSystem = true;
                }
                // Add Title checks to match transformFeedItems logic
                if (fi.Title == 'SYSTEM' || fi.Title == 'MILESTONE' || fi.Title == 'Owner Changed') {
                    isSystem = true;
                }
                
                if (isSystem) {
                    counts.systemCount++;
                } else if (fi.Visibility == 'AllUsers') {
                    counts.publicCount++;
                } else {
                    counts.internalCount++;
                }
            }
            
        } catch (Exception e) { System.debug('Error counting feeds: ' + e.getMessage()); }
        
        return counts;
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
    public static List<TimelineItem> getTimelineData(Id caseId, DateTime referenceDate, Integer limitSize, String sortDirection, Boolean debugMode, String lastSeenId) {
        if (limitSize == null || limitSize < 1) limitSize = 10;
        if (limitSize > 50) limitSize = 50; // Cap at 50 for heap safety
        if (String.isBlank(sortDirection)) sortDirection = 'desc';
        if (debugMode == null) debugMode = false;
        
        // Use inclusive operators to ensure we catch collisions
        String operator = (sortDirection == 'asc') ? '>=' : '<=';
        
        DateTime queryDate = (referenceDate == null) ? 
            (sortDirection == 'desc' ? DateTime.now().addSeconds(1) : DateTime.newInstance(1900, 1, 1)) : 
            referenceDate;
        
        String emailOrder = (sortDirection == 'asc') ? 'ASC' : 'DESC';
        String feedOrder = (sortDirection == 'asc') ? 'ASC' : 'DESC';
        
        // Fetch extra items to handle the boundary overlap and filtering.
        // We increase the buffer significantly to handle cases with many items having identical timestamps.
        Integer queryLimit = limitSize * 3;

        String emailQuery = 'SELECT Id, Subject, HtmlBody, TextBody, MessageDate, FromName, FromAddress, ' +
                           'ToAddress, CcAddress, BccAddress, CreatedBy.Name, Incoming ' +
                           'FROM EmailMessage ' +
                           'WHERE ParentId = :caseId AND Status != \'5\' AND MessageDate ' + operator + ' :queryDate ' +
                           'ORDER BY MessageDate ' + emailOrder + ', Id ' + emailOrder + ' LIMIT :queryLimit';
        
        if (debugMode) {
            System.debug('Email Query: ' + emailQuery);
            System.debug('Query Date: ' + queryDate);
        }

        List<EmailMessage> emailCandidates = Database.query(emailQuery);
        
        String feedQuery = 'SELECT Id, Body, CreatedDate, CreatedBy.Name, Type, Visibility, Title, Status, IsRichText, ' +
                          '(SELECT FieldName, OldValue, NewValue FROM FeedTrackedChanges), ' +
                          '(SELECT Id, RecordId, Type, Title FROM FeedAttachments WHERE Type IN (\'InlineImage\', \'Content\')) ' +
                          'FROM FeedItem ' +
                          'WHERE ParentId = :caseId AND Type != \'EmailMessageEvent\' AND CreatedDate ' + operator + ' :queryDate ' +
                          'ORDER BY CreatedDate ' + feedOrder + ', Id ' + feedOrder + ' LIMIT :queryLimit';
        
        if (debugMode) {
            System.debug('Feed Query: ' + feedQuery);
        }

        List<FeedItem> feedCandidates = Database.query(feedQuery);

        List<SObject> combinedRaw = new List<SObject>();
        combinedRaw.addAll((List<SObject>)emailCandidates);
        combinedRaw.addAll((List<SObject>)feedCandidates);

        List<RawItemWrapper> wrappers = new List<RawItemWrapper>();
        for(SObject obj : combinedRaw) {
            wrappers.add(new RawItemWrapper(obj, sortDirection));
        }
        wrappers.sort();
        
        List<EmailMessage> finalEmails = new List<EmailMessage>();
        List<FeedItem> finalFeeds = new List<FeedItem>();

        Integer count = 0;
        for(RawItemWrapper w : wrappers) {
            if (count >= limitSize) break;
            
            // CURSOR LOGIC: Skip items we have already seen
            if (referenceDate != null && w.sortDate == referenceDate && String.isNotBlank(lastSeenId)) {
                if (sortDirection == 'desc') {
                    // DESC: We want items (Date < Ref) OR (Date == Ref AND Id < LastId)
                    // So if Id >= LastId, we have seen it (or it came before/at the cut-off).
                    if ((String)w.obj.Id >= lastSeenId) continue;
                } else {
                    // ASC: We want items (Date > Ref) OR (Date == Ref AND Id > LastId)
                    // So if Id <= LastId, we have seen it.
                    if ((String)w.obj.Id <= lastSeenId) continue;
                }
            }
            
            if (w.obj instanceof EmailMessage) finalEmails.add((EmailMessage)w.obj);
            else finalFeeds.add((FeedItem)w.obj);
            count++;
        }
        
        // Memory optimization: Clear large raw lists before processing
        combinedRaw = null;
        wrappers = null;

        Map<Id, ConnectApi.FeedItem> connectMap = new Map<Id, ConnectApi.FeedItem>();
        List<String> idsToEnrich = new List<String>();
        Map<Id, Id> emailIdToFeedItemId = new Map<Id, Id>();
        
        // 1. Add standard feed items to enrichment
        for (FeedItem fi : finalFeeds) {
            if (fi.Type == 'TextPost' || fi.Type == 'ContentPost' || fi.Type == 'LinkPost' || fi.Type == 'AdvancedTextPost' || fi.Type == 'CaseCommentPost') {
                idsToEnrich.add(fi.Id);
            }
        }

        // 2. Add EmailMessageEvent items 
        // Note: For EmailMessageEvents, we also need to be careful with pagination if they were the boundary, 
        // but typically they are fetched ad-hoc here. We keep the original logic for simplicity unless deep paging hits them.
        List<FeedItem> emailEvents = Database.query(
            'SELECT Id FROM FeedItem WHERE ParentId = :caseId AND Type = \'EmailMessageEvent\' AND CreatedDate ' + operator + ' :queryDate LIMIT :limitSize'
        );
        for(FeedItem fi : emailEvents) {
            idsToEnrich.add(fi.Id);
        }

        if (!idsToEnrich.isEmpty()) {
            try {
                if (debugMode) System.debug('Enriching ' + idsToEnrich.size() + ' items via ConnectApi.');
                
                // Chunk requests to avoid ConnectApi 100-item limit
                Integer batchSizeConnect = 100;
                for (Integer i = 0; i < idsToEnrich.size(); i += batchSizeConnect) {
                    Integer endIndex = Math.min(i + batchSizeConnect, idsToEnrich.size());
                    List<String> batchIds = new List<String>();
                    for (Integer j = i; j < endIndex; j++) {
                        batchIds.add(idsToEnrich[j]);
                    }

                    List<ConnectApi.BatchResult> results = ConnectApi.ChatterFeeds.getFeedElementBatch(null, batchIds);
                    for (ConnectApi.BatchResult result : results) {
                        if (result.isSuccess()) {
                            Object res = result.getResult();
                            if (res instanceof ConnectApi.FeedItem) {
                                ConnectApi.FeedItem cfi = (ConnectApi.FeedItem)res;
                                connectMap.put(cfi.id, cfi);
                                
                                if (cfi.capabilities != null && cfi.capabilities.emailMessage != null) {
                                    emailIdToFeedItemId.put(cfi.capabilities.emailMessage.emailMessageId, cfi.id);
                                }
                            }
                        } else {
                            if (debugMode) System.debug('ConnectApi Batch Error: ' + result.getErrorMessage());
                        }
                    }
                }
            } catch (Exception e) { System.debug('ConnectAPI Error: ' + e.getMessage()); }
        }

        return processItems(finalEmails, finalFeeds, connectMap, emailIdToFeedItemId, sortDirection);
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
                
                // Tie-breaker: ID ASC
                if ((String)this.obj.Id < (String)other.obj.Id) return -1;
                if ((String)this.obj.Id > (String)other.obj.Id) return 1;
            } else {
                if (this.sortDate < other.sortDate) return 1;
                if (this.sortDate > other.sortDate) return -1;
                
                // Tie-breaker: ID DESC
                if ((String)this.obj.Id < (String)other.obj.Id) return 1;
                if ((String)this.obj.Id > (String)other.obj.Id) return -1;
            }
            return 0;
        }
    }

    // --- REFACTORED PROCESS ITEMS ---
    
    public class Context {
        public String baseUrl;
        public String fileBaseUrl;
        public Map<String, String> statusMap;
        public String sortDirection;
        public Map<Id, ConnectApi.FeedItem> connectMap;
        public Map<Id, Id> emailIdToFeedItemId;
        
        public Map<String, EmailRecordMatch> emailToRecordMap;
        public Map<String, String> documentIdToVersionId;
        public Map<String, String> versionIdToDocumentId;
        public Map<String, String> docIdToTitle;
        public Map<String, String> docIdToExtension;
        public Map<Id, List<CommentItem>> commentsMap;
        public Map<Id, List<ContentDocumentLink>> emailAttachments;
        public Map<Id, List<Attachment>> emailLegacyAttachments;
    }

    @TestVisible
    private static List<TimelineItem> processItems(List<EmailMessage> emails, List<FeedItem> feedItems, Map<Id, ConnectApi.FeedItem> connectMap, Map<Id, Id> emailIdToFeedItemId, String sortDirection) {
        Context ctx = new Context();
        ctx.baseUrl = getBaseUrl();
        ctx.fileBaseUrl = getFileBaseUrl();
        ctx.statusMap = getStatusMap();
        ctx.sortDirection = sortDirection;
        ctx.connectMap = connectMap;
        ctx.emailIdToFeedItemId = emailIdToFeedItemId;

        prepareContext(ctx, emails, feedItems);

        List<TimelineItem> combinedList = new List<TimelineItem>();
        combinedList.addAll(transformEmails(emails, ctx));
        combinedList.addAll(transformFeedItems(feedItems, ctx));
        combinedList.sort();
        
        return combinedList;
    }

    private static void prepareContext(Context ctx, List<EmailMessage> emails, List<FeedItem> feedItems) {
        Set<String> allEmailAddresses = new Set<String>();
        Set<Id> emailIds = new Set<Id>();
        for (EmailMessage em : emails) {
            emailIds.add(em.Id);
            if (String.isNotBlank(em.ToAddress)) allEmailAddresses.addAll(extractEmailAddresses(em.ToAddress));
            if (String.isNotBlank(em.CcAddress)) allEmailAddresses.addAll(extractEmailAddresses(em.CcAddress));
            if (String.isNotBlank(em.BccAddress)) allEmailAddresses.addAll(extractEmailAddresses(em.BccAddress));
            if (String.isNotBlank(em.FromAddress)) allEmailAddresses.addAll(extractEmailAddresses(em.FromAddress));
        }
        ctx.emailToRecordMap = buildEmailToRecordMap(allEmailAddresses);

        Set<String> contentDocIds = new Set<String>();
        Set<String> contentVersionIds = new Set<String>();
        Set<Id> allFeedIds = new Set<Id>();
        for (FeedItem fi : feedItems) allFeedIds.add(fi.Id);
        if (ctx.emailIdToFeedItemId != null) {
            for (Id emId : ctx.emailIdToFeedItemId.keySet()) {
                if (emailIds.contains(emId)) allFeedIds.add(ctx.emailIdToFeedItemId.get(emId));
            }
        }

        List<FeedComment> allComments = new List<FeedComment>();
        if (!allFeedIds.isEmpty()) {
            allComments = [SELECT Id, FeedItemId, CommentBody, CreatedDate, CreatedBy.Name FROM FeedComment WHERE FeedItemId IN :allFeedIds ORDER BY CreatedDate ASC];
        }

        Pattern idPattern = Pattern.compile('(069|068|00P)[a-zA-Z0-9]{12,15}\\b');
        for (FeedComment fc : allComments) {
            if (String.isNotBlank(fc.CommentBody)) {
                Matcher m = idPattern.matcher(fc.CommentBody);
                while (m.find()) {
                    String rid = m.group();
                    if (rid.startsWith('069')) contentDocIds.add(rid);
                    else if (rid.startsWith('068')) contentVersionIds.add(rid);
                }
            }
        }
        for (FeedItem cf : feedItems) {
            if (cf.FeedAttachments != null) {
                for (FeedAttachment fa : cf.FeedAttachments) {
                    String rId = (String)fa.RecordId;
                    if ((fa.Type == 'InlineImage' || fa.Type == 'Content') && String.isNotBlank(rId)) {
                        if (rId.startsWith('069')) contentDocIds.add(rId);
                        else if (rId.startsWith('068')) contentVersionIds.add(rId);
                    }
                }
            }
            if (String.isNotBlank(cf.Body)) {
                Matcher m = idPattern.matcher(cf.Body);
                while (m.find()) {
                    String rid = m.group();
                    if (rid.startsWith('069')) contentDocIds.add(rid);
                    else if (rid.startsWith('068')) contentVersionIds.add(rid);
                }
            }
        }
        for (EmailMessage em : emails) {
            if (String.isNotBlank(em.HtmlBody)) {
                Matcher m = idPattern.matcher(em.HtmlBody);
                while (m.find()) {
                    String rid = m.group();
                    if (rid.startsWith('069')) contentDocIds.add(rid);
                    else if (rid.startsWith('068')) contentVersionIds.add(rid);
                }
            }
        }

        ctx.documentIdToVersionId = new Map<String, String>();
        ctx.versionIdToDocumentId = new Map<String, String>();
        ctx.docIdToTitle = new Map<String, String>();
        ctx.docIdToExtension = new Map<String, String>();

        if (!contentDocIds.isEmpty() || !contentVersionIds.isEmpty()) {
            try {
                for (ContentVersion cv : [SELECT Id, ContentDocumentId, Title, FileExtension FROM ContentVersion WHERE (ContentDocumentId IN :contentDocIds OR Id IN :contentVersionIds) AND IsLatest = true]) {
                    String docId = cv.ContentDocumentId;
                    String verId = cv.Id;
                    
                    // Store BOTH 15 and 18 char versions for robust lookup
                    ctx.documentIdToVersionId.put(docId, verId);
                    ctx.documentIdToVersionId.put(docId.substring(0, 15), verId);
                    
                    ctx.versionIdToDocumentId.put(verId, docId);
                    ctx.versionIdToDocumentId.put(verId.substring(0, 15), docId);
                    
                    ctx.docIdToTitle.put(docId, cv.Title);
                    ctx.docIdToTitle.put(docId.substring(0, 15), cv.Title);
                    ctx.docIdToExtension.put(docId, cv.FileExtension);
                    ctx.docIdToExtension.put(docId.substring(0, 15), cv.FileExtension);
                }
            } catch (Exception e) {
                System.debug('Error querying ContentVersion: ' + e.getMessage());
            }
        }

        ctx.commentsMap = new Map<Id, List<CommentItem>>();
        for (FeedComment fc : allComments) {
            if (!ctx.commentsMap.containsKey(fc.FeedItemId)) ctx.commentsMap.put(fc.FeedItemId, new List<CommentItem>());
            String processedBody = fc.CommentBody;
            if (String.isNotBlank(processedBody)) {
                processedBody = fixRelativeImageUrls(processedBody, ctx.baseUrl, ctx.fileBaseUrl, ctx.documentIdToVersionId, null);
                processedBody = makeImagesClickable(processedBody, ctx.versionIdToDocumentId);
            }
            ctx.commentsMap.get(fc.FeedItemId).add(new CommentItem(fc.Id, processedBody, fc.CreatedBy.Name, fc.CreatedDate));
        }

        ctx.emailAttachments = new Map<Id, List<ContentDocumentLink>>();
        ctx.emailLegacyAttachments = new Map<Id, List<Attachment>>();
        if (!emailIds.isEmpty()) {
            for (ContentDocumentLink link : [SELECT Id, ContentDocumentId, LinkedEntityId, ContentDocument.Title, ContentDocument.FileExtension FROM ContentDocumentLink WHERE LinkedEntityId IN :emailIds]) {
                if (!ctx.emailAttachments.containsKey(link.LinkedEntityId)) ctx.emailAttachments.put(link.LinkedEntityId, new List<ContentDocumentLink>());
                ctx.emailAttachments.get(link.LinkedEntityId).add(link);
            }
            for (Attachment att : [SELECT Id, Name, ParentId FROM Attachment WHERE ParentId IN :emailIds]) {
                if (!ctx.emailLegacyAttachments.containsKey(att.ParentId)) ctx.emailLegacyAttachments.put(att.ParentId, new List<Attachment>());
                ctx.emailLegacyAttachments.get(att.ParentId).add(att);
            }
        }
    }

    private static List<TimelineItem> transformEmails(List<EmailMessage> emails, Context ctx) {
        List<TimelineItem> results = new List<TimelineItem>();
        for (EmailMessage em : emails) {
            TimelineItem item = new TimelineItem();
            item.id = em.Id;
            item.createdDate = em.MessageDate;
            item.category = 'Email';
            item.isInternal = false;
            item.isOutgoing = (em.Incoming == false);
            item.title = (em.Subject != null) ? '✉️ ' + em.Subject : 'No Subject';
            item.author = (em.Incoming == false && em.CreatedBy != null) ? em.CreatedBy.Name : em.FromName;
            item.recordUrl = '/' + em.Id;
            item.sortDir = ctx.sortDirection;
            item.emailTo = enrichEmailAddresses(em.ToAddress, ctx.emailToRecordMap);
            item.emailCc = enrichEmailAddresses(em.CcAddress, ctx.emailToRecordMap);
            item.emailBcc = enrichEmailAddresses(em.BccAddress, ctx.emailToRecordMap);
            item.emailFrom = enrichEmailAddresses(String.isNotBlank(em.FromAddress) ? em.FromAddress : em.FromName, ctx.emailToRecordMap);
            item.emailSubject = em.Subject;

            List<Attachment> availableAtts = ctx.emailLegacyAttachments.get(em.Id);
            try {
                if (String.isNotBlank(em.HtmlBody)) {
                    String processed = fixRelativeImageUrls(em.HtmlBody, ctx.baseUrl, ctx.fileBaseUrl, ctx.documentIdToVersionId, availableAtts);
                    item.body = makeImagesClickable(processed, ctx.versionIdToDocumentId);
                } else {
                    item.body = (em.TextBody != null) ? em.TextBody.replace('\n', '<br/>') : '';
                }
            } catch (Exception e) {
                System.debug('Error processing email body for ' + em.Id + ': ' + e.getMessage());
                item.body = (em.TextBody != null) ? em.TextBody.replace('\n', '<br/>') : '<i>(Content could not be displayed due to size or format limits)</i>';
            }

            // Attachments (Definitive Exclusion)
            Set<String> rawInlineIds = getUsedInlineIds(item.body);
            Set<String> inlineIds = new Set<String>();
            
            // Map every detected ID to BOTH its Version and Document counterparts
            for (String rid : rawInlineIds) {
                inlineIds.add(rid);
                inlineIds.add(rid.substring(0, 15));
                if (rid.startsWith('068') && ctx.versionIdToDocumentId.containsKey(rid)) {
                    String docId = ctx.versionIdToDocumentId.get(rid);
                    inlineIds.add(docId);
                    inlineIds.add(docId.substring(0, 15));
                } else if (rid.startsWith('069') && ctx.documentIdToVersionId.containsKey(rid)) {
                    String verId = ctx.documentIdToVersionId.get(rid);
                    inlineIds.add(verId);
                    inlineIds.add(verId.substring(0, 15));
                }
            }

            String bodyLower = item.body.toLowerCase();
            // Only suppress attachments if we are rendering HTML and might have inline images
            Boolean isHtml = String.isNotBlank(em.HtmlBody);
            
            List<String> cards = new List<String>();
            if (ctx.emailAttachments.containsKey(em.Id)) {
                for (ContentDocumentLink link : ctx.emailAttachments.get(em.Id)) {
                    String docId = link.ContentDocumentId;
                    Boolean isUsed = false;
                    
                    if (isHtml) {
                        isUsed = inlineIds.contains(docId) || inlineIds.contains(docId.substring(0, 15));
                        // SUPPRESSION LAYER 2: Check Version ID too
                        if (!isUsed && ctx.documentIdToVersionId.containsKey(docId)) {
                            String verId = ctx.documentIdToVersionId.get(docId);
                            if (inlineIds.contains(verId) || inlineIds.contains(verId.substring(0, 15))) isUsed = true;
                        }
                        // Fallback to name match only if name is distinctive
                        String title = link.ContentDocument.Title;
                        if (!isUsed && String.isNotBlank(title) && title.length() > 5 && bodyLower.contains(title.toLowerCase())) isUsed = true;
                    }
                    
                    if (isUsed) continue;
                    
                    cards.add(getAttachmentCardHtml(docId, link.ContentDocument.Title, link.ContentDocument.FileExtension));
                }
            }
            if (availableAtts != null) {
                for (Attachment att : availableAtts) {
                    String attId = att.Id;
                    Boolean isUsed = false;
                    
                    if (isHtml) {
                        isUsed = inlineIds.contains(attId) || inlineIds.contains(attId.substring(0, 15));
                        String name = att.Name;
                        if (!isUsed && String.isNotBlank(name) && name.length() > 5 && bodyLower.contains(name.toLowerCase())) isUsed = true;
                    }
                    
                    if (isUsed) continue;
                    
                    String name = att.Name;
                    String ext = (name != null && name.contains('.')) ? name.substringAfterLast('.') : '';
                    cards.add(getAttachmentCardHtml(attId, name, ext));
                }
            }
            item.attachmentsHtml = (!cards.isEmpty()) ? '<div style="margin-top:10px; padding-top:6px; border-top:1px solid #e5e5e5;">' + String.join(cards, '') + '</div>' : '';
            item.hasHistory = false;
            item.historyBody = '';

            if (ctx.emailIdToFeedItemId != null && ctx.emailIdToFeedItemId.containsKey(em.Id)) {
                Id feedId = ctx.emailIdToFeedItemId.get(em.Id);
                item.feedItemId = feedId;
                if (ctx.commentsMap.containsKey(feedId)) item.comments = ctx.commentsMap.get(feedId);
            }
            results.add(item);
        }
        return results;
    }

    private static List<TimelineItem> transformFeedItems(List<FeedItem> feeds, Context ctx) {
        List<TimelineItem> results = new List<TimelineItem>();
        for (FeedItem soqlFeedItem : feeds) {
            if (soqlFeedItem.Status == 'Draft') continue;
            if (soqlFeedItem.Type == 'EmailMessageEvent') continue;

            TimelineItem item = new TimelineItem();
            item.id = soqlFeedItem.Id;
            item.feedItemId = soqlFeedItem.Id;
            item.createdDate = soqlFeedItem.CreatedDate;
            item.hasHistory = false;
            item.recordUrl = '/' + soqlFeedItem.Id;
            item.attachmentsHtml = '';
            item.sortDir = ctx.sortDirection;

            if (ctx.commentsMap.containsKey(soqlFeedItem.Id)) item.comments = ctx.commentsMap.get(soqlFeedItem.Id);

            ConnectApi.FeedItem connectFeedItem = (ctx.connectMap != null) ? ctx.connectMap.get(soqlFeedItem.Id) : null;
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

            String formattedBody = soqlFeedItem.Body != null ? soqlFeedItem.Body : '';
            item.attachmentsHtml = getFeedAttachmentsHtml(soqlFeedItem, ctx.versionIdToDocumentId, ctx.docIdToTitle, ctx.docIdToExtension);

            String parsedResult = null;
            if (String.isNotBlank(formattedBody) && (formattedBody.containsIgnoreCase('feedEvent') || formattedBody.contains('{"fu"'))) parsedResult = parseFeedEventString(formattedBody, ctx.statusMap);

            if (parsedResult != null) item.body = parsedResult;
            else if (connectFeedItem != null) {
                Boolean isHandled = false;
                // Check for CaseComment capability (e.g. Case Merge)
                if (connectFeedItem.capabilities != null && connectFeedItem.capabilities.caseComment != null && String.isNotBlank(connectFeedItem.capabilities.caseComment.text)) {
                    item.body = connectFeedItem.capabilities.caseComment.text;
                    isHandled = true;
                    
                    // Specific Title for Merge events
                    if (item.body.containsIgnoreCase('merged with')) {
                        item.title = '⚙️ Cases Merged';
                    }
                    
                    if (ctx.sortDirection != null) System.debug('Found Case Comment Text: ' + item.body); // Use existing context var for debug trigger
                }
                
                String processed = formattedBody;
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
                for (String mentionText : mentionReplacements.keySet()) processed = processed.replace(mentionText, mentionReplacements.get(mentionText));
                String cleanBody = fixRelativeImageUrls(processed, ctx.baseUrl, ctx.fileBaseUrl, ctx.documentIdToVersionId, null);
                if (String.isNotBlank(cleanBody)) {
                    item.body = cleanHtml(cleanBody, true);
                    item.body = makeImagesClickable(item.body, ctx.versionIdToDocumentId);
                    for (String placeholder : mentionProtectionMap.keySet()) item.body = item.body.replace(placeholder, mentionProtectionMap.get(placeholder));
                } else if (!isHandled) {
                    item.body = '<i>[' + soqlFeedItem.Type + ']</i>';
                }
            } else {
                String cleanBody = fixRelativeImageUrls(formattedBody, ctx.baseUrl, ctx.fileBaseUrl, ctx.documentIdToVersionId, null);
                if (soqlFeedItem.FeedTrackedChanges != null && !soqlFeedItem.FeedTrackedChanges.isEmpty() && String.isBlank(formattedBody)) item.body = processTrackedChanges(soqlFeedItem.FeedTrackedChanges, ctx.statusMap);
                else if (String.isNotBlank(cleanBody)) {
                    item.body = cleanHtml(cleanBody, true); item.body = makeImagesClickable(item.body, ctx.versionIdToDocumentId);
                } else item.body = '<i>[' + soqlFeedItem.Type + ']</i>';
            }

            if (soqlFeedItem.IsRichText == false && String.isNotBlank(item.body)) {
                item.body = item.body.replace('\n', '<br/>');
            }
            results.add(item);
        }
        return results;
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
                // EXCLUDE InlineImage type as it is already in the body
                if (fa.Type == 'InlineImage') continue;

                String rId = (String)fa.RecordId;
                if (fa.Type == 'Content' && String.isNotBlank(rId)) {
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

    private static Set<String> getUsedInlineIds(String html) {
        Set<String> ids = new Set<String>();
        if (String.isBlank(html)) return ids;
        
        // Match ANY 15-18 char Salesforce ID starting with our prefixes anywhere in the text
        Pattern p = Pattern.compile('(069|068|00P)[a-zA-Z0-9]{12,15}');
        Matcher m = p.matcher(html);
        while (m.find()) {
            ids.add(m.group());
        }
        return ids;
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
    private static String fixRelativeImageUrls(String html, String baseUrl, String fileBaseUrl, Map<String, String> documentIdToVersionId, List<Attachment> legacyAtts) {
        if (String.isBlank(html)) return html;
        
        Pattern imgPattern = Pattern.compile('(?i)<img([^>]*?)>');
        Matcher m = imgPattern.matcher(html);
        
        String result = '';
        Integer lastEnd = 0;
        Integer attIndex = 0;
        
        while (m.find()) {
            result += html.substring(lastEnd, m.start());
            String fullTag = m.group();
            String attrs = m.group(1);
            
            Pattern srcPattern = Pattern.compile('(?i)src=["\']([^"\']+)["\']');
            Matcher srcMatcher = srcPattern.matcher(fullTag);
            String src = srcMatcher.find() ? srcMatcher.group(1) : '';
            String newSrc = src;
            
            // 1. Convert MyDomain to FileDomain
            if (src.containsIgnoreCase('.my.salesforce.com')) {
                newSrc = src.replace('.my.salesforce.com', '.file.force.com');
            }
            // 2. Process sfdc:// or /sfc/ links
            else if (src.startsWithIgnoreCase('sfdc://') || src.startsWithIgnoreCase('/sfc/')) {
                String id = src.startsWithIgnoreCase('sfdc://') ? src.substring(7) : src.substringAfter('/sfc/').substringBefore('?').substringBefore('/');
                if (id.length() >= 15) {
                    String cleanId = id.substring(0, 15);
                    if (cleanId.startsWith('00P')) {
                         newSrc = fileBaseUrl + '/servlet/servlet.FileDownload?file=' + cleanId;
                    } else if (documentIdToVersionId.containsKey(cleanId)) {
                         newSrc = fileBaseUrl + '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + documentIdToVersionId.get(cleanId) + '&operationContext=CHATTER&contentId=' + cleanId;
                    }
                }
            } 
            // 3. REPAIR: Only for internal/embedded relative links (cid:, /servlet/, etc.)
            // Skip any absolute https:// links that are NOT Salesforce (like signatures)
            else if (src.startsWithIgnoreCase('/') || src.startsWithIgnoreCase('cid:')) {
                if (legacyAtts != null && attIndex < legacyAtts.size()) {
                    newSrc = fileBaseUrl + '/servlet/servlet.FileDownload?file=' + legacyAtts[attIndex].Id;
                    attIndex++;
                } else if (src.startsWithIgnoreCase('/')) {
                    newSrc = fileBaseUrl + src;
                }
            }

            String cleanAttrs = attrs.replaceAll('(?i)src=["\'][^"\']*["\']', '').trim();
            result += '<img ' + cleanAttrs + ' src="' + newSrc + '">';
            lastEnd = m.end();
        }
        result += html.substring(lastEnd);
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
        Map<String, String> m = new Map<String, String>(); m.put('1', 'New'); m.put('2', 'On Hold'); m.put('3', 'Closed'); m.put('6', 'Open'); m.put('7', 'Working'); m.put('8', 'Waiting for Customer'); m.put('9', 'Solved'); m.put('10', 'Merged');
        try { for(Schema.PicklistEntry f : Case.Status.getDescribe().getPicklistValues()) { m.put(f.getValue(), f.getLabel()); m.put(f.getLabel(), f.getLabel()); } } catch (Exception e) { }
        return m;
    }
    @TestVisible private static String formatSystemTitle(String type) { if (type == 'TrackedChange') return 'Field Update'; if (type == 'ChangeStatusPost') return 'Status Changed'; if (type == 'CreateRecordEvent') return 'Record Created'; return type; }
    
    @TestVisible private static String makeImagesClickable(String html, Map<String, String> versionIdToDocId) {
        if (String.isBlank(html)) return html;
        String result = html;
        // Match <img> tags and capture their attributes and src
        Pattern imgPattern = Pattern.compile('(?i)<img([^>]*?)src=["\']([^"\']+)["\']([^>]*?)>');
        Matcher imgMatcher = imgPattern.matcher(result);
        
        while (imgMatcher.find()) {
            String fullMatch = imgMatcher.group(); 
            String beforeSrc = imgMatcher.group(1); 
            String srcUrl = imgMatcher.group(2); 
            String afterSrc = imgMatcher.group(3);
            
            String docId = null;
            
            // 1. Try to get ContentDocumentId (docId) directly from URL params
            if (srcUrl.contains('contentId=')) {
                docId = extractParam(srcUrl, 'contentId=');
            } 
            // 2. Try to get Attachment ID from legacy servlet URL
            else if (srcUrl.contains('file=')) {
                docId = extractParam(srcUrl, 'file=');
            }
            // 3. Try to get Version ID from query param
            else if (srcUrl.contains('versionId=')) {
                String versionId = extractParam(srcUrl, 'versionId=');
                docId = versionIdToDocId.get(versionId);
                if (docId == null && versionId != null && versionId.length() >= 15) {
                    docId = versionIdToDocId.get(versionId.substring(0, 15));
                }
            }
            // 4. Try to get Version ID from REST path (e.g. /version/download/068...)
            else if (srcUrl.contains('/version/download/')) {
                String versionId = srcUrl.substringAfter('/version/download/');
                // Truncate at next slash or query param if exists
                if (versionId.contains('/')) versionId = versionId.substringBefore('/');
                if (versionId.contains('?')) versionId = versionId.substringBefore('?');
                
                if (String.isNotBlank(versionId)) {
                    docId = versionIdToDocId.get(versionId);
                    if (docId == null && versionId.length() >= 15) {
                        docId = versionIdToDocId.get(versionId.substring(0, 15));
                    }
                }
            }
            
            // Ensure ID is a valid Salesforce ID format
            if (docId != null && (docId.length() < 15 || (!docId.startsWith('069') && !docId.startsWith('00P')))) {
                docId = null;
            }

            String replacement;
            if (String.isNotBlank(docId)) {
                // Use javascript:void(0) to prevent browser navigation/download
                // The LWC event handler will pick up the click via data-doc-id
                replacement = '<a href="javascript:void(0);" class="image-preview-link" data-doc-id="' + docId + '" style="display:block; max-width:80%; cursor:pointer;">' +
                              '<img' + beforeSrc + ' src="' + srcUrl + '"' + afterSrc + ' style="max-width:100%;"></a>';
            } else {
                // Fallback for external images: open in new tab
                String cleanUrl = srcUrl.replaceAll('(?i)([?&])rendition=[^&]*(&|$)', '$1').replaceAll('[?&]$', '');
                replacement = '<a href="' + cleanUrl + '" target="_blank" style="display:block; max-width:80%;">' +
                              '<img' + beforeSrc + ' src="' + srcUrl + '"' + afterSrc + ' style="max-width:100%; cursor:pointer;"></a>';
            }
            
            result = result.replace(fullMatch, replacement);
        }
        return result;
    }

    private static String extractParam(String url, String paramName) {
        try {
            Integer startIdx = url.indexOf(paramName) + paramName.length();
            Integer endIdx = url.indexOf('&', startIdx);
            if (endIdx == -1) endIdx = url.length();
            return url.substring(startIdx, endIdx);
        } catch (Exception e) { return null; }
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
        
        // 1. Protect Emails
        Map<String, String> emailMap = new Map<String, String>(); Integer emailIndex = 0;
        // Basic email regex: word chars, dots, dashes, percents, pluses before @, then domain chars after
        Pattern emailPattern = Pattern.compile('(?i)\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b');
        Matcher emailMatcher = emailPattern.matcher(html);
        while (emailMatcher.find()) {
            String email = emailMatcher.group();
            String placeholder = '[[[[EMAIL_ADDRESS_' + emailIndex + ']]]]';
            // We'll restore it as a mailto link
            String replacement = '<a href="mailto:' + email + '" style="color:#0176d3; text-decoration:none;">' + email + '</a>';
            emailMap.put(placeholder, replacement);
            
            // Replace FIRST occurrence to handle duplicates correctly without infinite loops in replaceAll
            html = html.replaceFirst(Pattern.quote(email), placeholder);
            emailIndex++;
        }

        String tldList = 'aero|app|dev|cloud|com|org|net|edu|gov|mil|biz|info|io|co|uk|be|eu|de|fr|it|es|nl|ru|ch|se|no|dk|pl|cs|cz|gr|ie|hu|pt|ro|sk|fi|bg|hr|lt|lv|ee|ca|au|nz|us|in|jp|cn|kr|br|mx|za|il|ae';
        // Simplified URL pattern since emails are gone
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
        
        // Restore Emails
        for (String placeholder : emailMap.keySet()) result = result.replace(placeholder, emailMap.get(placeholder));
        
        // Restore Tags
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