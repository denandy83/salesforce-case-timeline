@isTest
public class ND_TimelineTest_Final {

    // ============================================
    // BASIC INTEGRATION TESTS
    // ============================================
    
    @isTest
    static void testGetTimelineDataIntegration() {
        Case c = new Case(Subject = 'Test Case', Status = 'New');
        insert c;

        EmailMessage em = new EmailMessage(
            ParentId = c.Id,
            Subject = 'Test Email',
            HtmlBody = 'Hello World<br>-----Original Message-----<br>Old',
            Incoming = true,
            FromAddress = 'customer@test.com',
            Status = '0',
            MessageDate = DateTime.now()
        );
        insert em;

        FeedItem fi = new FeedItem(
            ParentId = c.Id,
            Body = 'Chatter Post',
            Type = 'TextPost'
        );
        insert fi;

        ConnectApi.FeedElementPage testPage = new ConnectApi.FeedElementPage();
        testPage.elements = new List<ConnectApi.FeedElement>();
        ConnectApi.ChatterFeeds.setTestGetFeedElementsFromFeed(null, ConnectApi.FeedType.Record, c.Id, testPage);

        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.getTimelineData(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, items, 'Should return a list');
        System.assert(items.size() >= 2, 'Should have at least Email and FeedItem');
    }

    // ============================================
    // EMAIL TESTS
    // ============================================
    
    @isTest
    static void testEmailWithAttachments() {
        Case c = new Case(Subject = 'Email Case', Status = 'New');
        insert c;

        EmailMessage em = new EmailMessage(
            ParentId = c.Id,
            Subject = 'Email with File',
            HtmlBody = 'Please see attached.',
            Incoming = true,
            FromAddress = 'test@test.com',
            MessageDate = DateTime.now()
        );
        insert em;

        ContentVersion cv = new ContentVersion(
            Title = 'contract.pdf', 
            PathOnClient = 'contract.pdf',
            VersionData = Blob.valueOf('PDF Data'),
            IsMajorVersion = true
        );
        insert cv;
        
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = em.Id,
            ContentDocumentId = docId,
            ShareType = 'V'
        );
        insert cdl;

        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>{em}, 
            new List<FeedItem>(), 
            null
        );
        Test.stopTest();

        System.assertEquals(1, items.size());
        Boolean hasAttachment = items[0].body.contains('contract.pdf') || items[0].body.contains('📕'); 
        System.assert(hasAttachment, 'Email body should contain the generated attachment card/link');
    }

    @isTest
    static void testEmailOutgoing() {
        Case c = new Case(Subject = 'Outgoing Email', Status = 'New');
        insert c;

        EmailMessage em = new EmailMessage(
            ParentId = c.Id,
            Subject = 'Sent Email',
            HtmlBody = 'Outgoing message',
            Incoming = false,
            ToAddress = 'customer@test.com',
            MessageDate = DateTime.now()
        );
        insert em;

        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>{em}, 
            new List<FeedItem>(), 
            null
        );
        Test.stopTest();

        System.assertEquals(1, items.size());
        System.assertEquals(true, items[0].isOutgoing, 'Should be marked as outgoing');
        System.assertEquals('Email', items[0].category);
    }

    @isTest
    static void testAllAttachmentIcons() {
        Case c = new Case(Subject='Icon Test', Status='New');
        insert c;
        
        EmailMessage em = new EmailMessage(
            ParentId = c.Id, 
            Subject = 'Files', 
            HtmlBody = 'Body', 
            Incoming = true, 
            FromAddress = 'test@test.com',
            MessageDate = DateTime.now()
        );
        insert em;
        
        List<ContentVersion> versions = new List<ContentVersion>();
        versions.add(new ContentVersion(Title='pic.jpg', PathOnClient='pic.jpg', VersionData=Blob.valueOf('x'), IsMajorVersion=true));
        versions.add(new ContentVersion(Title='sheet.xlsx', PathOnClient='sheet.xlsx', VersionData=Blob.valueOf('x'), IsMajorVersion=true));
        versions.add(new ContentVersion(Title='slide.pptx', PathOnClient='slide.pptx', VersionData=Blob.valueOf('x'), IsMajorVersion=true));
        versions.add(new ContentVersion(Title='archive.zip', PathOnClient='archive.zip', VersionData=Blob.valueOf('x'), IsMajorVersion=true));
        versions.add(new ContentVersion(Title='note.txt', PathOnClient='note.txt', VersionData=Blob.valueOf('x'), IsMajorVersion=true));
        versions.add(new ContentVersion(Title='doc.docx', PathOnClient='doc.docx', VersionData=Blob.valueOf('x'), IsMajorVersion=true));
        insert versions;
        
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for(ContentVersion cv : [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :versions]) {
            links.add(new ContentDocumentLink(LinkedEntityId = em.Id, ContentDocumentId = cv.ContentDocumentId, ShareType = 'V'));
        }
        insert links;
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>{em}, 
            new List<FeedItem>(), 
            null
        );
        Test.stopTest();
        
        String body = items[0].body;
        System.assert(body.contains('🖼️'), 'Should find image icon');
        System.assert(body.contains('📊'), 'Should find excel icon');
        System.assert(body.contains('📙'), 'Should find ppt icon');
        System.assert(body.contains('📦'), 'Should find zip icon');
        System.assert(body.contains('📝'), 'Should find txt icon');
        System.assert(body.contains('📘'), 'Should find docx icon');
    }

    // ============================================
    // FEED ITEM / CHATTER TESTS
    // ============================================
    
    @isTest
    static void testFeedItemBasic() {
        Case c = new Case(Subject = 'Feed Test', Status = 'New');
        insert c;

        // Use JSON deserialization to avoid triggering flows
        String nowStr = String.valueOf(DateTime.now()).replace(' ', 'T') + 'Z';
        String jsonStr = '[{"attributes": {"type": "FeedItem"}, "Id": "0D5000000000099", "Body": "Simple post", "Type": "TextPost", "Visibility": "AllUsers", "CreatedDate": "' + nowStr + '", "CreatedBy": {"Name": "Test User"}}]';
        List<FeedItem> mockItems = (List<FeedItem>)JSON.deserialize(jsonStr, List<FeedItem>.class);

        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            mockItems, 
            null
        );
        Test.stopTest();

        System.assertEquals(1, items.size());
        System.assertEquals('Public', items[0].category);
        System.assert(items[0].body.contains('Simple post'));
    }

    @isTest
    static void testFeedItemInternal() {
        Case c = new Case(Subject = 'Internal Note', Status = 'New');
        insert c;

        FeedItem fi = new FeedItem(
            ParentId = c.Id,
            Body = 'Internal note',
            Type = 'TextPost',
            Visibility = 'InternalUsers'
        );
        insert fi;

        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            new List<FeedItem>{fi}, 
            null
        );
        Test.stopTest();

        System.assertEquals(1, items.size());
        System.assertEquals('Internal', items[0].category);
        System.assertEquals(true, items[0].isInternal);
    }

    @isTest
    static void testFeedAttachments_ContentDocument() {
        ContentVersion cv = new ContentVersion(
            Title = 'Test Image',
            PathOnClient = 'test.jpg',
            VersionData = Blob.valueOf('Fake Image Data'),
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        
        String nowStr = String.valueOf(DateTime.now()).replace(' ', 'T') + 'Z';
        String jsonStr = '[{"attributes": {"type": "FeedItem", "url": "/services/data/v60.0/sobjects/FeedItem/0D5000000000001"}, "Id": "0D5000000000001", "Body": "Post with attachment", "Type": "TextPost", "CreatedDate": "' + nowStr + '", "FeedAttachments": {"totalSize": 1, "done": true, "records": [{"attributes": {"type": "FeedAttachment", "url": "/services/data/v60.0/sobjects/FeedAttachment/0D5000000000002"}, "Type": "InlineImage", "RecordId": "' + docId + '"}]}}]';

        List<FeedItem> mockItems = (List<FeedItem>)JSON.deserialize(jsonStr, List<FeedItem>.class);
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            mockItems, 
            null
        );
        Test.stopTest();
        
        System.assertEquals(1, items.size());
        Boolean processed = items[0].body.contains('servlet.shepherd') || items[0].body.contains('<img');
        System.assert(processed, 'Should have processed the attachment image');
    }

    @isTest
    static void testFeedAttachments_ContentVersion068Prefix() {
        String jsonStr = '[{"attributes": {"type": "FeedItem"}, "Id": "0D5000000000001", "Body": "Test", "Type": "TextPost", "CreatedDate": "2024-01-01T00:00:00Z", "FeedAttachments": {"totalSize": 1, "done": true, "records": [{"attributes": {"type": "FeedAttachment"}, "Type": "Content", "RecordId": "068000000000001"}]}}]';
        List<FeedItem> mockItems = (List<FeedItem>)JSON.deserialize(jsonStr, List<FeedItem>.class);
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            mockItems, 
            null
        );
        Test.stopTest();
        
        System.assert(!items.isEmpty(), 'Should process feed item with 068 prefix');
    }

    // ============================================
    // @MENTION TESTS
    // ============================================
    
    @isTest
    static void testConnectApiWithMention() {
        Case c = new Case(Subject='Mention Test', Status='New');
        insert c;
        
        ConnectApi.FeedElementPage testPage = new ConnectApi.FeedElementPage();
        testPage.elements = new List<ConnectApi.FeedElement>();

        ConnectApi.FeedItem mockItem = new ConnectApi.FeedItem();
        mockItem.id = '0D5000000000005'; 
        mockItem.createdDate = DateTime.now();
        mockItem.visibility = ConnectApi.FeedItemVisibilityType.AllUsers; 
        mockItem.body = new ConnectApi.FeedBody();
        mockItem.body.messageSegments = new List<ConnectApi.MessageSegment>();
        
        ConnectApi.TextSegment textSeg = new ConnectApi.TextSegment();
        textSeg.text = 'Hello ';
        mockItem.body.messageSegments.add(textSeg);

        ConnectApi.MentionSegment mentionSeg = new ConnectApi.MentionSegment();
        mentionSeg.text = '@John Doe';
        mentionSeg.record = new ConnectApi.UserSummary();
        mentionSeg.record.id = UserInfo.getUserId();
        mockItem.body.messageSegments.add(mentionSeg);
        
        testPage.elements.add(mockItem);

        FeedItem matchingSoqlItem = new FeedItem(ParentId = c.Id, Body = 'Hello @John Doe', Type = 'TextPost');
        insert matchingSoqlItem;
        mockItem.id = matchingSoqlItem.Id; 

        ConnectApi.ChatterFeeds.setTestGetFeedElementsFromFeed(null, ConnectApi.FeedType.Record, c.Id, testPage);

        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> results = ND_CaseTimelineController.getTimelineData(c.Id);
        Test.stopTest();
        
        Boolean found = false;
        for (ND_CaseTimelineController.TimelineItem item : results) {
            if (item.id == matchingSoqlItem.Id) {
                // Verify mention-link class is present (for JavaScript interception)
                if(item.body.contains('class="mention-link"') && item.body.contains('data-record-id=')) {
                    found = true;
                }
            }
        }
        System.assert(found, 'Should linkify mention with mention-link class and data-record-id');
    }

    @isTest
    static void testMentionProtectionFromLinkification() {
        Case c = new Case(Subject='Mention Protection', Status='New');
        insert c;
        
        ConnectApi.FeedElementPage testPage = new ConnectApi.FeedElementPage();
        testPage.elements = new List<ConnectApi.FeedElement>();

        ConnectApi.FeedItem mockItem = new ConnectApi.FeedItem();
        mockItem.id = '0D5000000000006'; 
        mockItem.createdDate = DateTime.now();
        mockItem.visibility = ConnectApi.FeedItemVisibilityType.AllUsers; 
        mockItem.body = new ConnectApi.FeedBody();
        mockItem.body.messageSegments = new List<ConnectApi.MessageSegment>();
        
        ConnectApi.TextSegment textSeg = new ConnectApi.TextSegment();
        textSeg.text = 'Visit www.google.com and talk to ';
        mockItem.body.messageSegments.add(textSeg);

        ConnectApi.MentionSegment mentionSeg = new ConnectApi.MentionSegment();
        mentionSeg.text = '@Jane Smith';
        mentionSeg.record = new ConnectApi.UserSummary();
        mentionSeg.record.id = UserInfo.getUserId();
        mockItem.body.messageSegments.add(mentionSeg);
        
        testPage.elements.add(mockItem);

        FeedItem matchingSoqlItem = new FeedItem(
            ParentId = c.Id, 
            Body = 'Visit www.google.com and talk to @Jane Smith', 
            Type = 'TextPost'
        );
        insert matchingSoqlItem;
        mockItem.id = matchingSoqlItem.Id;

        ConnectApi.ChatterFeeds.setTestGetFeedElementsFromFeed(null, ConnectApi.FeedType.Record, c.Id, testPage);

        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> results = ND_CaseTimelineController.getTimelineData(c.Id);
        Test.stopTest();
        
        Boolean foundMention = false;
        Boolean foundUrl = false;
        for (ND_CaseTimelineController.TimelineItem item : results) {
            if (item.id == matchingSoqlItem.Id) {
                // Verify mention link is present
                if(item.body.contains('class="mention-link"')) foundMention = true;
                // Verify URL was linkified
                if(item.body.contains('href="https://www.google.com"')) foundUrl = true;
            }
        }
        System.assert(foundMention, 'Mention should be preserved');
        System.assert(foundUrl, 'URL should be linkified');
    }

    // ============================================
    // STATUS CHANGE / TRACKED CHANGES TESTS
    // ============================================
    
    @isTest
    static void testTrackedChangesWithProcessTrackedChanges() {
        // Test processTrackedChanges directly with mock data
        Map<String, String> statusMap = ND_CaseTimelineController.getStatusMap();
        
        // Create mock FeedTrackedChange with feedEvent JSON
        String feedEventJson = '{"fu":[{"ov":"1","fn":"Status","nv":"9"}]}';
        
        // We can't actually insert TrackedChange FeedItems, so we test the processing method directly
        // This tests the core status mapping logic
        Test.startTest();
        
        // Test the parseFeedEventString method which handles the JSON
        String bodyWithFeedEvent = 'feedEvent: {"fu":[{"ov":"1","fn":"Status","nv":"9"}]}';
        String result = ND_CaseTimelineController.parseFeedEventString(bodyWithFeedEvent, statusMap);
        
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should parse feedEvent JSON');
        System.assert(result.contains('Status'), 'Should contain Status field');
        // Should map "1" to readable label and "9" to readable label
        System.assert(!result.contains('1 &rarr; 9'), 'Should not contain raw IDs');
    }

    @isTest
    static void testTrackedChangesNormalFieldProcessing() {
        // Test that normal field changes are processed correctly
        Map<String, String> statusMap = ND_CaseTimelineController.getStatusMap();
        
        Test.startTest();
        
        // We test the status mapping logic through parseFeedEventString
        String bodyWithStatus = 'feedEvent: {"fu":[{"ov":"1","fn":"Status","nv":"9"}]}';
        String result = ND_CaseTimelineController.parseFeedEventString(bodyWithStatus, statusMap);
        
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Should parse status change');
        System.assert(result.contains('Status'), 'Should show Status field');
    }

    @isTest
    static void testParseFeedEventString() {
        Case c = new Case(Subject = 'Parse Test', Status = 'New');
        insert c;
        
        FeedItem fi = new FeedItem(
            ParentId = c.Id,
            Body = 'feedEvent: {"fu":[{"ov":"1","fn":"Status","nv":"9"}]}',
            Type = 'ChangeStatusPost'
        );
        insert fi;

        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            new List<FeedItem>{fi}, 
            null
        );
        Test.stopTest();

        System.assertEquals(1, items.size());
        // Should parse the JSON and map status codes
        System.assert(items[0].body.contains('Status'), 'Should contain Status field');
        System.assert(!items[0].body.contains('"fu"'), 'Should not contain raw JSON');
    }

    // ============================================
    // URL LINKIFICATION TESTS
    // ============================================
    
    @isTest
    static void testLinkifyBasicUrls() {
        Case c = new Case(Subject='Link Test', Status='New');
        insert c;
        
        String body = 'Visit https://salesforce.com and www.google.com also check apex.class.com';
        FeedItem fi = new FeedItem(ParentId = c.Id, Body = body, Type = 'TextPost');
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            new List<FeedItem>{fi}, 
            null
        );
        Test.stopTest();
        
        String result = items[0].body;
        System.assert(result.contains('<a href="https://salesforce.com"'), 'Should linkify https URL');
        System.assert(result.contains('<a href="https://www.google.com"'), 'Should linkify www URL');
        System.assert(result.contains('<a href="https://apex.class.com"'), 'Should linkify domain.tld');
    }

    @isTest
    static void testLinkifyEdgeCases() {
        Case c = new Case(Subject='Edge Cases', Status='New');
        insert c;
        
        String complexBody = 'Visit apex.class.com now. Also (salesforce.com) is cool. Check Google.com. <p>www.broken.com)</p>';
        FeedItem fi = new FeedItem(ParentId = c.Id, Body = complexBody, Type = 'TextPost');
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            new List<FeedItem>{fi}, 
            null
        );
        Test.stopTest();
        
        String result = items[0].body;
        System.assert(result.contains('<a href="https://apex.class.com"'), 'Should linkify apex.class.com');
        System.assert(result.contains('(<a href="https://salesforce.com"'), 'Should linkify (salesforce.com)');
        System.assert(result.contains('<a href="https://www.broken.com"'), 'Should linkify broken.com');
        System.assert(result.contains('</p>'), 'Should preserve closing P tag');
    }

    @isTest
    static void testLinkifyWithParenthesis() {
        Case c = new Case(Subject='Parenthesis', Status='New');
        insert c;
        
        String body = 'Check this link (https://example.com/page?param=1) and this one';
        FeedItem fi = new FeedItem(ParentId = c.Id, Body = body, Type = 'TextPost');
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            new List<FeedItem>{fi}, 
            null
        );
        Test.stopTest();
        
        String result = items[0].body;
        System.assert(result.contains('https://example.com/page?param=1'), 'Should preserve URL with params');
        System.assert(result.contains(') and'), 'Should keep closing parenthesis outside link');
    }

    // ============================================
    // CODE BLOCK TESTS
    // ============================================
    
    @isTest
    static void testCodeBlockFormatting() {
        Case c = new Case(Subject='Code', Status='New');
        insert c;
        
        String codeBody = 'Here is code: <code>debug("test");\nreturn true;</code>';
        FeedItem fi = new FeedItem(ParentId=c.Id, Body=codeBody, Type='TextPost');
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            new List<FeedItem>{fi}, 
            null
        );
        Test.stopTest();
        
        System.assert(items[0].body.contains('class="code-wrapper"'), 'Should wrap code');
        System.assert(items[0].body.contains('<span class="line-num">1</span>'), 'Should have line numbers');
        System.assert(items[0].body.contains('class="copy-btn"'), 'Should have copy button');
    }

    @isTest
    static void testCodeBlockProtectsUrls() {
        Case c = new Case(Subject='Code URL', Status='New');
        insert c;
        
        String codeBody = 'Check this: <code>http://do-not-link-me.com</code>';
        FeedItem fi = new FeedItem(ParentId = c.Id, Body = codeBody, Type = 'TextPost');
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            new List<FeedItem>{fi}, 
            null
        );
        Test.stopTest();
        
        // Verify URL inside code block was NOT linkified
        System.assert(!items[0].body.contains('<a href="http://do-not-link-me.com"'), 'Should NOT linkify URLs inside code blocks');
    }

    // ============================================
    // IMAGE HANDLING TESTS
    // ============================================
    
    @isTest
    static void testRelativeUrlRegex() {
        String html = '<img src="/sfc/servlet.shepherd/version/download/123">';
        String baseUrl = 'https://base.com';
        String fileBaseUrl = 'https://file.force.com';
        Map<String, String> emptyMap = new Map<String, String>();
        
        Test.startTest();
        String fixed = ND_CaseTimelineController.fixRelativeImageUrls(html, baseUrl, fileBaseUrl, emptyMap);
        Test.stopTest();
        
        System.assert(fixed.contains(baseUrl + '/sfc/'), 'Should prepend base URL to relative /sfc/ paths');
    }

    @isTest
    static void testSfdcProtocolImageUrl() {
        ContentVersion cv = new ContentVersion(
            Title = 'Test', 
            PathOnClient = 'test.jpg', 
            VersionData = Blob.valueOf('x'), 
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        
        Map<String, String> docToVersion = new Map<String, String>();
        docToVersion.put(docId, cv.Id);
        
        String html = '<img src="sfdc://' + docId + '">';
        String baseUrl = 'https://base.com';
        String fileBaseUrl = 'https://file.force.com';
        
        Test.startTest();
        String fixed = ND_CaseTimelineController.fixRelativeImageUrls(html, baseUrl, fileBaseUrl, docToVersion);
        Test.stopTest();
        
        System.assert(fixed.contains('servlet.shepherd'), 'Should convert sfdc:// to servlet URL');
        System.assert(fixed.contains(cv.Id), 'Should include version ID');
    }

    @isTest
    static void testMakeImagesClickable() {
        Case c = new Case(Subject='Clickable Image', Status='New');
        insert c;
        
        String body = 'Look: <img src="https://google.com/cat.jpg">';
        FeedItem fi = new FeedItem(ParentId=c.Id, Body=body, Type='TextPost');
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            new List<FeedItem>{fi}, 
            null
        );
        Test.stopTest();
        
        System.assert(items[0].body.contains('<a href="https://google.com/cat.jpg"'), 'Should wrap images in a link');
    }

    @isTest
    static void testMakeImagesClickableWithContentDocument() {
        ContentVersion cv = new ContentVersion(
            Title = 'pic.png', 
            PathOnClient = 'pic.png', 
            VersionData = Blob.valueOf('x'), 
            IsMajorVersion = true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        
        String body = '<img src="https://file.force.com/sfc/servlet.shepherd/version/renditionDownload?rendition=THUMB720BY480&versionId=' + cv.Id + '&operationContext=CHATTER&contentId=' + docId + '">';
        
        Map<String, String> versionToDoc = new Map<String, String>();
        versionToDoc.put(cv.Id, docId);
        
        Test.startTest();
        String result = ND_CaseTimelineController.makeImagesClickable(body, versionToDoc);
        Test.stopTest();
        
        System.assert(result.contains('href="/lightning/r/ContentDocument/' + docId + '/view"'), 'Should link to ContentDocument preview');
        System.assert(result.contains('class="image-preview-link"'), 'Should have image-preview-link class');
    }

    // ============================================
    // CATEGORIZATION TESTS
    // ============================================
    
    @isTest
    static void testSystemCategorization() {
        Case c = new Case(Subject = 'System', Status = 'New');
        insert c;

        // Can only test types we can actually insert
        FeedItem activityEvent = new FeedItem(ParentId = c.Id, Type = 'ActivityEvent');
        FeedItem createEvent = new FeedItem(ParentId = c.Id, Type = 'CreateRecordEvent');
        
        Test.startTest();
        insert new List<FeedItem>{activityEvent, createEvent};

        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            new List<FeedItem>{activityEvent, createEvent}, 
            null
        );
        Test.stopTest();

        for(ND_CaseTimelineController.TimelineItem item : items) {
            System.assertEquals('System', item.category, 'All should be System category');
            System.assertEquals(true, item.isInternal, 'All should be internal');
        }
    }

    @isTest
    static void testDraftAndEmailMessageEventFiltering() {
        Case c = new Case(Subject = 'Filter Test', Status = 'New');
        insert c;

        FeedItem draft = new FeedItem(ParentId = c.Id, Body = 'Draft', Type = 'TextPost', Status = 'Draft');
        FeedItem emailEvent = new FeedItem(ParentId = c.Id, Type = 'EmailMessageEvent');
        FeedItem valid = new FeedItem(ParentId = c.Id, Body = 'Valid', Type = 'TextPost');
        
        insert new List<FeedItem>{draft, emailEvent, valid};

        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            new List<FeedItem>{draft, emailEvent, valid}, 
            null
        );
        Test.stopTest();

        System.assertEquals(1, items.size(), 'Should only include valid FeedItem');
        System.assertEquals(valid.Id, items[0].id);
    }

    // ============================================
    // HELPER METHOD TESTS
    // ============================================
    
    @isTest
    static void testGetBaseUrl() {
        Test.startTest();
        String baseUrl = ND_CaseTimelineController.getBaseUrl();
        Test.stopTest();
        
        System.assertNotEquals(null, baseUrl, 'Should return base URL');
        System.assert(!baseUrl.endsWith('/'), 'Should not end with slash');
    }

    @isTest
    static void testGetFileBaseUrl() {
        Test.startTest();
        String fileBaseUrl = ND_CaseTimelineController.getFileBaseUrl();
        Test.stopTest();
        
        System.assertNotEquals(null, fileBaseUrl, 'Should return file base URL');
        System.assert(!fileBaseUrl.endsWith('/'), 'Should not end with slash');
    }

    @isTest
    static void testFormatSystemTitle() {
        Test.startTest();
        String title1 = ND_CaseTimelineController.formatSystemTitle('TrackedChange');
        String title2 = ND_CaseTimelineController.formatSystemTitle('ChangeStatusPost');
        String title3 = ND_CaseTimelineController.formatSystemTitle('CreateRecordEvent');
        String title4 = ND_CaseTimelineController.formatSystemTitle('UnknownType');
        Test.stopTest();
        
        System.assertEquals('Field Update', title1);
        System.assertEquals('Status Changed', title2);
        System.assertEquals('Record Created', title3);
        System.assertEquals('UnknownType', title4, 'Should return original type if not mapped');
    }

    @isTest
    static void testGetStatusMap() {
        Test.startTest();
        Map<String, String> statusMap = ND_CaseTimelineController.getStatusMap();
        Test.stopTest();
        
        System.assertNotEquals(null, statusMap, 'Should return status map');
        System.assert(statusMap.containsKey('1'), 'Should have hardcoded mappings');
        System.assert(statusMap.containsKey('9'), 'Should have Solved mapping');
    }

    // ============================================
    // SORTING AND COMPARISON TESTS
    // ============================================
    
    @isTest
    static void testTimelineItemSorting() {
        ND_CaseTimelineController.TimelineItem item1 = new ND_CaseTimelineController.TimelineItem();
        item1.createdDate = DateTime.now().addDays(-2);
        
        ND_CaseTimelineController.TimelineItem item2 = new ND_CaseTimelineController.TimelineItem();
        item2.createdDate = DateTime.now().addDays(-1);
        
        ND_CaseTimelineController.TimelineItem item3 = new ND_CaseTimelineController.TimelineItem();
        item3.createdDate = DateTime.now();
        
        List<ND_CaseTimelineController.TimelineItem> items = new List<ND_CaseTimelineController.TimelineItem>{
            item1, item3, item2
        };
        
        Test.startTest();
        items.sort();
        Test.stopTest();
        
        // After sorting, newest should be first (descending order)
        System.assertEquals(item3.createdDate, items[0].createdDate, 'Newest should be first');
        System.assertEquals(item1.createdDate, items[2].createdDate, 'Oldest should be last');
    }

    // ============================================
    // COVERAGE BOOSTER / EDGE CASES
    // ============================================
    
    @isTest
    static void testComprehensiveCoverage() {
        Case c = new Case(Subject = 'Coverage Case', Status = 'New');
        insert c;

        // Email with history
        EmailMessage em = new EmailMessage(
            ParentId = c.Id, 
            Subject = 'Reply', 
            HtmlBody = 'New<br>-----Original Message-----<br>Old', 
            FromAddress = 'test@test.com', 
            Incoming = true,
            MessageDate = DateTime.now()
        );
        insert em;

        // Add attachment to email
        ContentVersion cv = new ContentVersion(
            Title='f.txt', 
            PathOnClient='f.txt', 
            VersionData=Blob.valueOf('x'), 
            IsMajorVersion=true
        );
        insert cv;
        ContentDocumentLink cdl = new ContentDocumentLink(
            LinkedEntityId = em.Id, 
            ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId, 
            ShareType = 'V'
        );
        insert cdl;

        // Activity event (should fall through to Type display)
        FeedItem activityPost = new FeedItem(ParentId = c.Id, Type = 'ActivityEvent');
        insert activityPost;

        // Code block post
        FeedItem codePost = new FeedItem(
            ParentId = c.Id, 
            Body = 'Code: <code>http://no-link.com</code>', 
            Type = 'TextPost'
        );
        insert codePost;

        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>{em}, 
            new List<FeedItem>{activityPost, codePost}, 
            null
        );
        Test.stopTest();

        Boolean foundActivity = false;
        Boolean foundCode = false;
        Boolean foundEmail = false;
        
        for(ND_CaseTimelineController.TimelineItem item : items) {
            if(item.id == activityPost.Id) {
                System.assert(item.body.contains('ActivityEvent'), 'Should show Type as fallback');
                foundActivity = true;
            }
            if(item.id == codePost.Id) {
                System.assert(!item.body.contains('<a href="http://no-link.com"'), 'Should NOT linkify in code');
                foundCode = true;
            }
            if(item.id == em.Id) {
                System.assert(item.hasHistory, 'Email should have history');
                System.assert(item.historyBody.contains('f.txt') || item.historyBody.contains('📝'), 'History should have attachment');
                foundEmail = true;
            }
        }
        
        System.assert(foundActivity, 'Should process activity event');
        System.assert(foundCode, 'Should process code post');
        System.assert(foundEmail, 'Should process email');
    }
}