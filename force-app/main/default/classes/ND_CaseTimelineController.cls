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

    @AuraEnabled
    public static List<TimelineItem> getTimelineData(Id caseId) {
        // 1. QUERY EMAIL MESSAGES
        List<EmailMessage> emails = [SELECT Id, Subject, HtmlBody, TextBody, MessageDate, FromName, CreatedBy.Name, Incoming 
                                     FROM EmailMessage 
                                     WHERE ParentId = :caseId 
                                     AND Status != '5' 
                                     ORDER BY MessageDate DESC];

        // 2. GET FEED ITEMS VIA CONNECTAPI (for proper @mention formatting)
        // Note: ConnectAPI doesn't work in test context, so we wrap in try-catch
        ConnectApi.FeedElementPage feedPage = null;
        try {
            // Simple method signature: communityId, feedType, subjectId
            feedPage = ConnectApi.ChatterFeeds.getFeedElementsFromFeed(
                null,  // communityId - null means internal org
                ConnectApi.FeedType.Record, 
                caseId
            );
            System.debug('ConnectAPI returned ' + (feedPage != null ? feedPage.elements.size() : 0) + ' elements');
        } catch (Exception e) {
            System.debug('ConnectAPI not available (likely test context): ' + e.getMessage());
            // feedPage will remain null - processItems will handle this gracefully
        }
        
        // 3. QUERY FEED ITEMS WITH ATTACHMENTS (for images and tracked changes)
        List<FeedItem> feedItems = [SELECT Id, Body, CreatedDate, CreatedBy.Name, Type, Visibility, Title, Status, IsRichText,
                                         (SELECT FieldName, OldValue, NewValue FROM FeedTrackedChanges),
                                         (SELECT Id, RecordId, Type FROM FeedAttachments WHERE Type IN ('InlineImage', 'Content'))
                                    FROM FeedItem 
                                    WHERE ParentId = :caseId 
                                    ORDER BY CreatedDate DESC];

        System.debug('=== TIMELINE DEBUG START ===');
        System.debug('Found ' + feedItems.size() + ' FeedItems');
        
        // 4. PASS TO PROCESSING LOGIC
        return processItems(emails, feedItems, feedPage);
    }

    @TestVisible 
    private static List<TimelineItem> processItems(List<EmailMessage> emails, List<FeedItem> feedItems, ConnectApi.FeedElementPage feedPage) {
        List<TimelineItem> combinedList = new List<TimelineItem>();
        Map<String, String> statusMap = getStatusMap();
        
        // Create a map of FeedItems by ID for quick lookup
        Map<Id, FeedItem> feedItemMap = new Map<Id, FeedItem>();
        for (FeedItem fi : feedItems) {
            feedItemMap.put(fi.Id, fi);
        }
        
        // Get the base URL for fixing relative image paths
        String baseUrl = getBaseUrl();
        String fileBaseUrl = getFileBaseUrl();
        System.debug('Base URL: ' + baseUrl);
        System.debug('File Base URL: ' + fileBaseUrl);
        
        // Build maps of ContentDocument IDs to ContentVersion IDs (both directions)
        Map<String, String> documentIdToVersionId = new Map<String, String>();
        Map<String, String> versionIdToDocumentId = new Map<String, String>();
        
        // Collect ContentDocument IDs AND ContentVersion IDs from FeedAttachments
        Set<String> contentDocIds = new Set<String>();
        Set<String> contentVersionIds = new Set<String>();

        for (FeedItem cf : feedItems) {
            if (cf.FeedAttachments != null && !cf.FeedAttachments.isEmpty()) {
                for (FeedAttachment fa : cf.FeedAttachments) {
                    if ((fa.Type == 'InlineImage' || fa.Type == 'Content') && String.isNotBlank(fa.RecordId)) {
                        String recordId = fa.RecordId;
                        String prefix = recordId.substring(0, 3);
                        
                        if (prefix == '069') {
                            contentDocIds.add(recordId);
                            System.debug('Found ContentDocumentId: ' + recordId);
                        } else if (prefix == '068') {
                            contentVersionIds.add(recordId);
                            System.debug('Found ContentVersionId: ' + recordId);
                        }
                    }
                }
            }
        }

        // Query ContentVersions for BOTH ContentDocumentIds AND ContentVersionIds
        if (!contentDocIds.isEmpty() || !contentVersionIds.isEmpty()) {
            try {
                List<ContentVersion> versions = [SELECT Id, ContentDocumentId
                                                FROM ContentVersion 
                                                WHERE (ContentDocumentId IN :contentDocIds OR Id IN :contentVersionIds)
                                                AND IsLatest = true];
                
                System.debug('ContentVersion query returned ' + versions.size() + ' records');
                
                for (ContentVersion cv : versions) {
                    documentIdToVersionId.put(cv.ContentDocumentId, cv.Id);
                    versionIdToDocumentId.put(cv.Id, cv.ContentDocumentId); // Reverse map
                    System.debug('Mapped: ContentDoc ' + cv.ContentDocumentId + ' <-> Version ' + cv.Id);
                }
            } catch (Exception e) {
                System.debug('ERROR querying ContentVersion: ' + e.getMessage());
            }
        }

        // --- PROCESS EMAILS ---
        // First, collect all email IDs to query attachments
        Set<Id> emailIds = new Set<Id>();
        for (EmailMessage em : emails) {
            emailIds.add(em.Id);
        }
        
        // Query ContentDocumentLinks for email attachments
        Map<Id, List<ContentDocumentLink>> emailAttachments = new Map<Id, List<ContentDocumentLink>>();
        if (!emailIds.isEmpty()) {
            for (ContentDocumentLink link : [SELECT Id, ContentDocumentId, LinkedEntityId, ContentDocument.Title
                                             FROM ContentDocumentLink 
                                             WHERE LinkedEntityId IN :emailIds]) {
                if (!emailAttachments.containsKey(link.LinkedEntityId)) {
                    emailAttachments.put(link.LinkedEntityId, new List<ContentDocumentLink>());
                }
                emailAttachments.get(link.LinkedEntityId).add(link);
            }
        }
        
        // Get ContentVersions for email attachments
        Set<Id> emailContentDocIds = new Set<Id>();
        for (List<ContentDocumentLink> links : emailAttachments.values()) {
            for (ContentDocumentLink link : links) {
                emailContentDocIds.add(link.ContentDocumentId);
            }
        }
        
        Map<Id, Id> emailDocToVersion = new Map<Id, Id>();
        if (!emailContentDocIds.isEmpty()) {
            for (ContentVersion cv : [SELECT Id, ContentDocumentId 
                                      FROM ContentVersion 
                                      WHERE ContentDocumentId IN :emailContentDocIds 
                                      AND IsLatest = true]) {
                emailDocToVersion.put(cv.ContentDocumentId, cv.Id);
            }
        }
        
        for(EmailMessage em : emails) {
            System.debug('===== EMAIL DEBUG START =====');
            System.debug('Email ID: ' + em.Id);
            System.debug('Subject: ' + em.Subject);
            
            TimelineItem item = new TimelineItem();
            item.id = em.Id;
            item.createdDate = em.MessageDate;
            item.category = 'Email'; 
            item.isInternal = false;
            item.isOutgoing = (em.Incoming == false);
            item.title = (em.Subject != null) ? '✉️ ' + em.Subject : 'No Subject';
            item.author = (em.Incoming == false && em.CreatedBy != null) ? em.CreatedBy.Name : em.FromName;
            item.recordUrl = '/' + em.Id;

            ND_EmailCompare.ComparisonResult res = ND_EmailCompare.parse(
                em.HtmlBody, em.TextBody, null, null
            );
            
            item.body = cleanHtml(res.newContent); // Don't linkify emails - they have rich HTML
            item.historyBody = cleanHtml(res.historyContent); // Don't linkify emails - they have rich HTML
            item.hasHistory = res.hasHistory;
            
            // Add email attachments as clickable cards (not full images)
            if (emailAttachments.containsKey(em.Id)) {
                List<String> attachmentCards = new List<String>();
                for (ContentDocumentLink link : emailAttachments.get(em.Id)) {
                    // Create a nice attachment card
                    String fileName = link.ContentDocument.Title;
                    String docId = link.ContentDocumentId;
                    
                    // Get file extension and choose icon
                    String fileIcon = '📄'; // Default document
                    String lowerFileName = fileName.toLowerCase();
                    if (lowerFileName.endsWith('.png') || lowerFileName.endsWith('.jpg') || lowerFileName.endsWith('.jpeg') || lowerFileName.endsWith('.gif') || lowerFileName.endsWith('.webp')) {
                        fileIcon = '🖼️';
                    } else if (lowerFileName.endsWith('.pdf')) {
                        fileIcon = '📕';
                    } else if (lowerFileName.endsWith('.doc') || lowerFileName.endsWith('.docx')) {
                        fileIcon = '📘';
                    } else if (lowerFileName.endsWith('.xls') || lowerFileName.endsWith('.xlsx') || lowerFileName.endsWith('.csv')) {
                        fileIcon = '📊';
                    } else if (lowerFileName.endsWith('.ppt') || lowerFileName.endsWith('.pptx')) {
                        fileIcon = '📙';
                    } else if (lowerFileName.endsWith('.txt')) {
                        fileIcon = '📝';
                    } else if (lowerFileName.endsWith('.zip') || lowerFileName.endsWith('.rar') || lowerFileName.endsWith('.7z')) {
                        fileIcon = '📦';
                    }
                    
                    // Create smaller, more compact attachment card with in-page preview
                    String attachmentCard = '<a href="javascript:void(0);" class="image-preview-link" data-doc-id="' + docId + '" data-record-type="ContentDocument" style="display:inline-block; margin:4px 8px 4px 0; padding:6px 10px; background:#f3f2f2; border:1px solid #c9c7c5; border-radius:3px; text-decoration:none; color:#0176d3; font-size:0.8125rem; cursor:pointer;">' +
                        '<span style="margin-right:6px;">' + fileIcon + '</span>' + fileName +
                        '</a>';
                    attachmentCards.add(attachmentCard);
                    System.debug('Added email attachment card: ' + fileName);
                }
                
                if (!attachmentCards.isEmpty()) {
                    item.body += '<div style="margin-top:10px; padding-top:6px; border-top:1px solid #e5e5e5;">' + String.join(attachmentCards, '') + '</div>';
                    if (String.isNotBlank(item.historyBody)) {
                        item.historyBody += '<div style="margin-top:10px; padding-top:6px; border-top:1px solid #e5e5e5;">' + String.join(attachmentCards, '') + '</div>';
                    }
                }
            }
            
            System.debug('===== EMAIL DEBUG END =====');
            
            combinedList.add(item);
        }

        // --- PROCESS FEED ITEMS (via ConnectAPI for @mentions) ---
        if (feedPage != null && feedPage.elements != null && !feedPage.elements.isEmpty()) {
            System.debug('Processing FeedItems via ConnectAPI: ' + feedPage.elements.size() + ' elements');
            for(ConnectApi.FeedElement element : feedPage.elements) {
            if (!(element instanceof ConnectApi.FeedItem)) continue;
            
            ConnectApi.FeedItem connectFeedItem = (ConnectApi.FeedItem)element;
            FeedItem soqlFeedItem = feedItemMap.get(connectFeedItem.id);
            
            if (soqlFeedItem == null) continue; // Skip if not found in SOQL
            if (soqlFeedItem.Status == 'Draft') continue;
            if (soqlFeedItem.Type == 'EmailMessageEvent') continue;

            TimelineItem item = new TimelineItem();
            item.id = connectFeedItem.id;
            item.createdDate = connectFeedItem.createdDate;
            item.author = (connectFeedItem.actor != null) ? connectFeedItem.actor.name : 'System';
            item.hasHistory = false;
            item.recordUrl = '/' + connectFeedItem.id;

            System.debug('--- FeedItem (ID: ' + connectFeedItem.id + ') ---');
            System.debug('Type: ' + soqlFeedItem.Type);

            // Categorization
            Boolean isSystemType = (soqlFeedItem.Type == 'TrackedChange' || 
                                    soqlFeedItem.Type == 'CreateRecordEvent' || 
                                    soqlFeedItem.Type == 'ActivityEvent' ||
                                    soqlFeedItem.Type == 'CaseCommentPost' || 
                                    soqlFeedItem.Type == 'ChangeStatusPost' || 
                                    (soqlFeedItem.CreatedBy != null && soqlFeedItem.CreatedBy.Name == 'Automated Process') ||
                                    soqlFeedItem.Title == 'SYSTEM' || 
                                    soqlFeedItem.Title == 'MILESTONE' ||
                                    soqlFeedItem.Title == 'Owner Changed');

            if (isSystemType) {
                item.category = 'System';
                item.isInternal = true; 
                if (soqlFeedItem.Title == 'SYSTEM' || soqlFeedItem.Title == 'MILESTONE' || soqlFeedItem.Title == 'Owner Changed') {
                    item.title = '⚙️ ' + soqlFeedItem.Title;
                } else {
                    item.title = '⚙️ ' + formatSystemTitle(soqlFeedItem.Type);
                }
            } else if (connectFeedItem.visibility == ConnectApi.FeedItemVisibilityType.AllUsers) {
                item.category = 'Public';
                item.isInternal = false; 
                item.title = '💬 Public Post';
            } else {
                item.category = 'Internal';
                item.isInternal = true; 
                item.title = '🔒 Internal Note';
            }
            
            // --- PROCESS BODY: Start with SOQL Body (has formatting), then enhance @mentions ---
            String formattedBody = soqlFeedItem.Body != null ? soqlFeedItem.Body : '';
            
            // Build a map of @mention text to clickable links from ConnectAPI
            Map<String, String> mentionReplacements = new Map<String, String>();
            if (connectFeedItem.body != null && connectFeedItem.body.messageSegments != null) {
                for (ConnectApi.MessageSegment segment : connectFeedItem.body.messageSegments) {
                    if (segment instanceof ConnectApi.MentionSegment) {
                        ConnectApi.MentionSegment m = (ConnectApi.MentionSegment)segment;
                        // Map the plain text @mention to clickable link (Lightning navigation format)
                        String mentionText = m.text; // e.g., "@Andy Cassiers"
                        String mentionLink = '<a href="/lightning/r/' + m.record.id + '/view" style="color:#0176d3; font-weight:bold; text-decoration:none;">' + m.text + '</a>';
                        mentionReplacements.put(mentionText, mentionLink);
                    }
                }
            }
            
            // Replace @mentions in the formatted body
            for (String mentionText : mentionReplacements.keySet()) {
                formattedBody = formattedBody.replace(mentionText, mentionReplacements.get(mentionText));
            }
            
            System.debug('RAW FORMATTED BODY (first 500 chars):');
            System.debug(formattedBody.length() > 500 ? formattedBody.substring(0, 500) : formattedBody);
            
            // Fix relative image URLs in the body
            String cleanBody = fixRelativeImageUrls(formattedBody, baseUrl, fileBaseUrl, documentIdToVersionId);
            
            // Handle ContentPost images from FeedAttachments - ADD AT END
            List<String> attachmentImages = new List<String>();
            if (soqlFeedItem.FeedAttachments != null && !soqlFeedItem.FeedAttachments.isEmpty()) {
                for (FeedAttachment fa : soqlFeedItem.FeedAttachments) {
                    if ((fa.Type == 'Content' || fa.Type == 'InlineImage') && String.isNotBlank(fa.RecordId)) {
                        String recordId = fa.RecordId;
                        String versionId = documentIdToVersionId.get(recordId);
                        
                        // If recordId is already a version ID (068), use it directly
                        if (recordId.startsWith('068')) {
                            versionId = recordId;
                        }
                        
                        System.debug('Processing attachment - RecordId: ' + recordId + ', VersionId: ' + versionId);
                        if (String.isNotBlank(versionId)) {
                            // Check if image is already in the body (inline image)
                            if (!cleanBody.contains(versionId)) {
                                String thumbUrl = fileBaseUrl + '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + 
                                    versionId + '&operationContext=CHATTER&contentId=' + recordId;
                                
                                // Get ContentDocumentId for preview
                                String docId = versionIdToDocumentId.get(versionId);
                                if (String.isBlank(docId) && recordId.startsWith('069')) {
                                    docId = recordId; // RecordId is already a ContentDocumentId
                                }
                                
                                // Make image clickable to open preview (not new tab)
                                if (String.isNotBlank(docId)) {
                                    attachmentImages.add('<a href="javascript:void(0);" class="image-preview-link" data-doc-id="' + docId + '" data-record-type="ContentDocument" style="display:block; margin-top:10px; max-width:80%;"><img src="' + thumbUrl + '" alt="Attachment" style="max-width:100%; cursor:pointer;" /></a>');
                                } else {
                                    // Fallback to full URL if no docId
                                    String fullUrl = fileBaseUrl + '/sfc/servlet.shepherd/version/download/' + versionId;
                                    attachmentImages.add('<a href="' + fullUrl + '" target="_blank" style="display:block; margin-top:10px; max-width:80%;"><img src="' + thumbUrl + '" alt="Attachment" style="max-width:100%; cursor:pointer;" /></a>');
                                }
                                System.debug('Added clickable attachment image to list');
                            }
                        }
                    }
                }
            }
            
            // Add attachment images at the END
            if (!attachmentImages.isEmpty()) {
                cleanBody += '<br/>' + String.join(attachmentImages, '<br/>');
            }

            // Handle Tracked Changes (System posts with no body)
            String parsedResult = null;
            if (cleanBody.containsIgnoreCase('feedEvent') || cleanBody.contains('{"fu"')) {
                parsedResult = parseFeedEventString(cleanBody, statusMap);
            }

            if (parsedResult != null) {
                item.body = parsedResult;
            }
            else if (soqlFeedItem.FeedTrackedChanges != null && !soqlFeedItem.FeedTrackedChanges.isEmpty() && String.isBlank(formattedBody)) {
                List<String> changes = new List<String>();
                for (FeedTrackedChange ftc : soqlFeedItem.FeedTrackedChanges) {
                    String field = (ftc.FieldName != null) ? ftc.FieldName : 'Field';
                    String oldV = String.valueOf(ftc.OldValue);
                    String newV = String.valueOf(ftc.NewValue);

                    if (field == 'Status') {
                        if (statusMap.containsKey(oldV)) oldV = statusMap.get(oldV);
                        if (statusMap.containsKey(newV)) newV = statusMap.get(newV);
                    }
                    if (oldV == null) oldV = '(blank)';
                    if (newV == null) newV = '(blank)';
                    
                    if (oldV == '(blank)' && newV == '(blank)') {
                         changes.add('<b>' + field + '</b>: <i>(Updated)</i>');
                    } else {
                         changes.add('<b>' + field + '</b>: ' + oldV + ' &rarr; ' + newV);
                    }
                }
                item.body = String.join(changes, '<br/>');
            } 
            else if (String.isNotBlank(cleanBody)) {
                item.body = cleanHtml(cleanBody, true); // Linkify URLs in FeedItems
                item.body = makeImagesClickable(item.body, versionIdToDocumentId); // Make all images clickable
                System.debug('FINAL BODY (first 500 chars):');
                System.debug(item.body.length() > 500 ? item.body.substring(0, 500) : item.body);
            } else {
                // Only show type if we have no body and no attachments were added
                item.body = '<i>[' + soqlFeedItem.Type + ']</i>';
            }

            combinedList.add(item);
        }
        } else {
            // FALLBACK: Process FeedItems from SOQL when ConnectAPI is unavailable
            System.debug('Processing FeedItems via SOQL fallback: ' + feedItems.size() + ' items');
            for(FeedItem soqlFeedItem : feedItems) {
                if (soqlFeedItem.Status == 'Draft') continue;
                if (soqlFeedItem.Type == 'EmailMessageEvent') continue;

                TimelineItem item = new TimelineItem();
                item.id = soqlFeedItem.Id;
                item.createdDate = soqlFeedItem.CreatedDate;
                item.author = (soqlFeedItem.CreatedBy != null) ? soqlFeedItem.CreatedBy.Name : 'System';
                item.hasHistory = false;
                item.recordUrl = '/' + soqlFeedItem.Id;

                System.debug('--- FeedItem SOQL (ID: ' + soqlFeedItem.Id + ') ---');
                System.debug('Type: ' + soqlFeedItem.Type);

                // Categorization
                Boolean isSystemType = (soqlFeedItem.Type == 'TrackedChange' || 
                                        soqlFeedItem.Type == 'CreateRecordEvent' || 
                                        soqlFeedItem.Type == 'ActivityEvent' ||
                                        soqlFeedItem.Type == 'CaseCommentPost' || 
                                        soqlFeedItem.Type == 'ChangeStatusPost' || 
                                        (soqlFeedItem.CreatedBy != null && soqlFeedItem.CreatedBy.Name == 'Automated Process') ||
                                        soqlFeedItem.Title == 'SYSTEM' || 
                                        soqlFeedItem.Title == 'MILESTONE' ||
                                        soqlFeedItem.Title == 'Owner Changed');

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
                
                // Use SOQL Body (no @mention formatting available)
                String formattedBody = soqlFeedItem.Body != null ? soqlFeedItem.Body : '';
                
                // Fix relative image URLs in the body
                String cleanBody = fixRelativeImageUrls(formattedBody, baseUrl, fileBaseUrl, documentIdToVersionId);
                
                // Handle ContentPost images from FeedAttachments
                if (soqlFeedItem.FeedAttachments != null && !soqlFeedItem.FeedAttachments.isEmpty()) {
                    for (FeedAttachment fa : soqlFeedItem.FeedAttachments) {
                        if ((fa.Type == 'Content' || fa.Type == 'InlineImage') && String.isNotBlank(fa.RecordId)) {
                            String contentDocId = fa.RecordId;
                            String versionId = documentIdToVersionId.get(contentDocId);
                            if (String.isNotBlank(versionId)) {
                                if (!cleanBody.contains(versionId)) {
                                    String imgUrl = fileBaseUrl + '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + 
                                        versionId + '&operationContext=CHATTER&contentId=' + contentDocId;
                                    String separator = String.isNotBlank(cleanBody) ? '<br/>' : '';
                                    cleanBody += separator + '<img src="' + imgUrl + '" alt="' + (soqlFeedItem.Title != null ? soqlFeedItem.Title : 'Image') + '" style="max-width:80%; margin-top:10px;" />';
                                }
                            }
                        }
                    }
                }

                // Handle Tracked Changes (System posts with no body)
                String parsedResult = null;
                if (cleanBody.containsIgnoreCase('feedEvent') || cleanBody.contains('{"fu"')) {
                    parsedResult = parseFeedEventString(cleanBody, statusMap);
                }

                if (parsedResult != null) {
                    item.body = parsedResult;
                }
                else if (soqlFeedItem.FeedTrackedChanges != null && !soqlFeedItem.FeedTrackedChanges.isEmpty() && String.isBlank(formattedBody)) {
                    List<String> changes = new List<String>();
                    for (FeedTrackedChange ftc : soqlFeedItem.FeedTrackedChanges) {
                        String field = (ftc.FieldName != null) ? ftc.FieldName : 'Field';
                        String oldV = String.valueOf(ftc.OldValue);
                        String newV = String.valueOf(ftc.NewValue);

                        if (field == 'Status') {
                            if (statusMap.containsKey(oldV)) oldV = statusMap.get(oldV);
                            if (statusMap.containsKey(newV)) newV = statusMap.get(newV);
                        }
                        if (oldV == null) oldV = '(blank)';
                        if (newV == null) newV = '(blank)';
                        
                        if (oldV == '(blank)' && newV == '(blank)') {
                             changes.add('<b>' + field + '</b>: <i>(Updated)</i>');
                        } else {
                             changes.add('<b>' + field + '</b>: ' + oldV + ' &rarr; ' + newV);
                        }
                    }
                    item.body = String.join(changes, '<br/>');
                } 
                else if (String.isNotBlank(cleanBody)) {
                    item.body = cleanHtml(cleanBody, true); // Linkify URLs in FeedItems
                    item.body = makeImagesClickable(item.body, versionIdToDocumentId); // Make all images clickable
                } else {
                    item.body = '<i>[' + soqlFeedItem.Type + ']</i>';
                }

                combinedList.add(item);
            }
        }

        System.debug('=== TIMELINE DEBUG END ===');
        combinedList.sort();
        return combinedList;
    }

    // --- NEW HELPER: Fix Relative Image URLs ---
    @TestVisible
    private static String fixRelativeImageUrls(String html, String baseUrl, String fileBaseUrl, Map<String, String> documentIdToVersionId) {
        if (String.isBlank(html)) {
            System.debug('fixRelativeImageUrls: Skipping - html is blank');
            return html;
        }
        
        String result = html;
        Integer replacementCount = 0;
        
        // Pattern 0: SFDC protocol images - sfdc://[ContentDocumentId]
        Pattern p0 = Pattern.compile('(?i)<img([^>]*?)src="sfdc://([^"]+)"');
        Matcher m0 = p0.matcher(result);
        while (m0.find()) {
            String fullMatch = m0.group();
            String beforeSrc = m0.group(1);
            String contentDocumentId = m0.group(2);
            
            System.debug('Processing SFDC URL with ContentDocumentId: ' + contentDocumentId);
            
            // Get the ContentVersion ID from our map
            String contentVersionId = documentIdToVersionId.get(contentDocumentId);
            System.debug('Found ContentVersionId: ' + contentVersionId);
            
            String replacement;
            if (String.isNotBlank(contentVersionId)) {
                // Build the proper image URL using the file.force.com domain
                replacement = '<img' + beforeSrc + 'src="' + fileBaseUrl + 
                    '/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + 
                    contentVersionId + '&operationContext=CHATTER&contentId=' + contentDocumentId + '"';
                System.debug('REPLACED (SFDC Protocol): ' + replacement);
            } else {
                System.debug('WARNING: No ContentVersionId found for documentId: ' + contentDocumentId);
                // Keep original as fallback
                replacement = fullMatch;
            }
            
            result = result.replace(fullMatch, replacement);
            if (String.isNotBlank(contentVersionId)) {
                replacementCount++;
            }
        }
        
        // Pattern 1: <img src="/sfc/servlet/...">
        if (String.isNotBlank(baseUrl)) {
            Pattern p1 = Pattern.compile('(?i)<img([^>]*?)src="(/sfc/[^"]+)"');
            Matcher m1 = p1.matcher(result);
            while (m1.find()) {
                String fullMatch = m1.group();
                String beforeSrc = m1.group(1);
                String relativeUrl = m1.group(2);
                String replacement = '<img' + beforeSrc + 'src="' + baseUrl + relativeUrl + '"';
                result = result.replace(fullMatch, replacement);
                replacementCount++;
                System.debug('REPLACED (Pattern 1): ' + fullMatch + ' -> ' + replacement);
            }
        }
        
        System.debug('Total image URL replacements: ' + replacementCount);
        return result;
    }

    // --- NEW HELPER: Get File Base URL ---
    @TestVisible
    private static String getFileBaseUrl() {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        
        // Convert from my.salesforce.com to file.force.com
        if (baseUrl.contains('.my.salesforce.com')) {
            baseUrl = baseUrl.replace('.my.salesforce.com', '.file.force.com');
        } else if (baseUrl.contains('.lightning.force.com')) {
            baseUrl = baseUrl.replace('.lightning.force.com', '.file.force.com');
        }
        
        // Remove trailing slash if present
        if (baseUrl.endsWith('/')) {
            baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        }
        
        return baseUrl;
    }

    // --- NEW HELPER: Get Base URL ---
    @TestVisible
    private static String getBaseUrl() {
        String baseUrl = URL.getOrgDomainUrl().toExternalForm();
        
        // Remove trailing slash if present
        if (baseUrl.endsWith('/')) {
            baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        }
        
        return baseUrl;
    }

    // --- HELPER: JSON PARSER ---
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
                    
                    if (field == 'Status') {
                        if (statusMap.containsKey(oldV)) oldV = statusMap.get(oldV);
                        if (statusMap.containsKey(newV)) newV = statusMap.get(newV);
                        
                        if (String.isBlank(oldV) || oldV == 'null') oldV = '(blank)';
                        if (String.isBlank(newV) || newV == 'null') newV = '(blank)';
                        
                        return '<b>' + field + '</b>: ' + oldV + ' &rarr; ' + newV;
                    }
                }
            }
            return null;
        } catch (Exception e) {
            return null; 
        }
    }

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

    private static String formatSystemTitle(String type) {
        if (type == 'TrackedChange') return 'Field Update';
        if (type == 'ChangeStatusPost') return 'Status Changed';
        if (type == 'CreateRecordEvent') return 'Record Created';
        return type;
    }
    
    private static String makeImagesClickable(String html, Map<String, String> versionIdToDocId) {
        if (String.isBlank(html)) return html;
        
        String result = html;
        
        // Match all img tags
        Pattern imgPattern = Pattern.compile('(?i)<img([^>]*?)src="([^"]+)"([^>]*?)>');
        Matcher imgMatcher = imgPattern.matcher(result);
        
        List<String> matches = new List<String>();
        List<String> replacements = new List<String>();
        
        while (imgMatcher.find()) {
            String fullMatch = imgMatcher.group();
            String beforeSrc = imgMatcher.group(1);
            String srcUrl = imgMatcher.group(2);
            String afterSrc = imgMatcher.group(3);
            
            // Extract versionId from URL (e.g., versionId=068...)
            String versionId = null;
            if (srcUrl.contains('versionId=')) {
                Integer startIdx = srcUrl.indexOf('versionId=') + 10;
                Integer endIdx = srcUrl.indexOf('&', startIdx);
                if (endIdx == -1) endIdx = srcUrl.length();
                versionId = srcUrl.substring(startIdx, endIdx);
            }
            
            // Get ContentDocumentId from versionId
            String docId = versionIdToDocId.get(versionId);
            
            String replacement;
            if (String.isNotBlank(docId)) {
                // Use javascript:void(0) to prevent navigation - JS will handle the click via NavigationMixin
                replacement = '<a href="javascript:void(0);" class="image-preview-link" data-doc-id="' + docId + '" data-record-type="ContentDocument" style="display:block; max-width:80%;"><img' + 
                    beforeSrc + 'src="' + srcUrl + '"' + afterSrc + ' style="max-width:100%; cursor:pointer;"></a>';
            } else {
                // Fallback: just make it clickable to open full image
                String fullUrl = srcUrl.replaceAll('([?&])rendition=[^&]*(&|$)', '$1').replaceAll('[?&]$', '');
                replacement = '<a href="' + fullUrl + '" target="_blank" style="display:block; max-width:80%;"><img' + 
                    beforeSrc + 'src="' + srcUrl + '"' + afterSrc + ' style="max-width:100%; cursor:pointer;"></a>';
            }
            
            matches.add(fullMatch);
            replacements.add(replacement);
        }
        
        // Replace all matches
        for (Integer i = 0; i < matches.size(); i++) {
            result = result.replace(matches[i], replacements[i]);
        }
        
        return result;
    }

    private static String cleanHtml(String html) {
        return cleanHtml(html, false); // Default: don't linkify (for emails)
    }
    
    private static String cleanHtml(String html, Boolean shouldLinkify) {
        if (String.isBlank(html)) return '';
        
        // Basic cleanup
        html = html.replace('<html', '<div').replace('</html>', '</div>')
                   .replace('<body', '<div').replace('</body>', '</div>')
                   .replace('<!DOCTYPE html>', '');
        
        // Linkify URLs - ONLY for FeedItems, NOT for emails (which have rich HTML that can break)
        if (shouldLinkify) {
            html = linkifyUrls(html);
        }
        
        // Style code blocks
        html = styleCodeBlocks(html);
        
        return html;
    }
    
    // Convert plain text URLs to clickable links (but NOT inside code blocks or HTML attributes)
    private static String linkifyUrls(String html) {
        if (String.isBlank(html)) return html;
        
        // First, temporarily replace code blocks with placeholders to protect them
        Map<String, String> codeBlocks = new Map<String, String>();
        Pattern codePattern = Pattern.compile('(?is)<code>(.*?)</code>');
        Matcher codeMatcher = codePattern.matcher(html);
        Integer codeIndex = 0;
        
        while (codeMatcher.find()) {
            String placeholder = '___CODE_BLOCK_' + codeIndex + '___';
            codeBlocks.put(placeholder, codeMatcher.group(0));
            html = html.replace(codeMatcher.group(0), placeholder);
            codeIndex++;
        }
        
        // Now linkify URLs - but ONLY in safe contexts (after >, whitespace, opening paren, or at start)
        // This avoids breaking href="..." or src="..." attributes
        
        // Pattern 1: URLs after >, whitespace, or opening paren (safe contexts)
        // Matches: https://, http://, www., or domain.tld
        // Now allows ) in URLs but stops at ) followed by whitespace or < or end of string
        html = html.replaceAll('([>\\s(])((?:https?://|www\\.|[a-zA-Z0-9][a-zA-Z0-9-]*\\.(?:com|org|net|edu|gov|mil|be|lu|nl|de|fr|uk|io|co|info|biz|us|ca|au|jp|cn|in|br|ru|za|it|es|se|no|dk|fi|pl|ch|at|cz|ie|pt|gr|hu|ro|sk|bg|hr|lt|lv|ee|si|cy|mt|is|aero))[^\\s<>]*?)(?=(\\)|\\s|<|$))', '$1<a href="$2" target="_blank" rel="noopener noreferrer">$2</a>');
        
        // Pattern 2: URLs at the very start of the string
        html = html.replaceAll('^((?:https?://|www\\.|[a-zA-Z0-9][a-zA-Z0-9-]*\\.(?:com|org|net|edu|gov|mil|be|lu|nl|de|fr|uk|io|co|info|biz|us|ca|au|jp|cn|in|br|ru|za|it|es|se|no|dk|fi|pl|ch|at|cz|ie|pt|gr|hu|ro|sk|bg|hr|lt|lv|ee|si|cy|mt|is|aero))[^\\s<>]*?)(?=(\\)|\\s|<|$))', '<a href="$1" target="_blank" rel="noopener noreferrer">$1</a>');
        
        // Fix URLs without protocol (add https://) - only for www. and domain.tld, NOT http(s)://
        html = html.replaceAll('<a href="(www\\.[^"]+)"', '<a href="https://$1"');
        html = html.replaceAll('<a href="((?!https?://)[a-zA-Z0-9][a-zA-Z0-9-]*\\.(?:com|org|net|edu|gov|mil|be|lu|nl|de|fr|uk|io|co|info|biz|us|ca|au|jp|cn|in|br|ru|za|it|es|se|no|dk|fi|pl|ch|at|cz|ie|pt|gr|hu|ro|sk|bg|hr|lt|lv|ee|si|cy|mt|is|aero)[^"]*)"', '<a href="https://$1"');
        
        // Restore code blocks
        for (String placeholder : codeBlocks.keySet()) {
            html = html.replace(placeholder, codeBlocks.get(placeholder));
        }
        
        return html;
    }
    
    // Style code blocks with line numbers and copy button
    private static String styleCodeBlocks(String html) {
        if (String.isBlank(html)) return html;
        
        // Find all <code> blocks and enhance them
        Pattern p = Pattern.compile('(?is)<code>(.*?)</code>');
        Matcher m = p.matcher(html);
        
        String result = html;
        Integer blockId = 0;
        
        while (m.find()) {
            String codeContent = m.group(1);
            String fullMatch = m.group(0);
            
            // Escape for data attribute
            String escapedContent = codeContent.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n');
            
            // Add line numbers
            String[] lines = codeContent.split('\n');
            String numberedCode = '';
            for (Integer i = 0; i < lines.size(); i++) {
                numberedCode += '<div class="code-line"><span class="line-num">' + (i + 1) + '</span><span class="line-content">' + lines[i] + '</span></div>';
            }
            
            // Create ID for this block
            String codeId = 'code-block-' + blockId;
            blockId++;
            
            // Create wrapper with copy button (onclick handled by JS)
            String replacement = '<div class="code-wrapper">' +
                '<button class="copy-btn" data-code="' + escapedContent + '">Copy</button>' +
                '<code id="' + codeId + '" class="numbered-code">' + numberedCode + '</code>' +
                '</div>';
            
            result = result.replace(fullMatch, replacement);
        }
        
        return result;
    }
}