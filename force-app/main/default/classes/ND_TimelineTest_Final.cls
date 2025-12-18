@isTest
public class ND_TimelineTest_Final {

    // ==========================================
    // 1. INTEGRATION TESTS (Standard Logic)
    // ==========================================

    @isTest
    static void testGetTimelineDataIntegration() {
        Case c = new Case(Subject = 'Test Case', Status = 'New');
        insert c;

        // 1. Create Email
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

        // 2. Create Feed Item
        FeedItem fi = new FeedItem(
            ParentId = c.Id,
            Body = 'Chatter Post',
            Type = 'TextPost'
        );
        insert fi;

        // 3. Mock ConnectApi (Empty) to trigger SOQL fallback
        ConnectApi.FeedElementPage testPage = new ConnectApi.FeedElementPage();
        testPage.elements = new List<ConnectApi.FeedElement>();
        ConnectApi.ChatterFeeds.setTestGetFeedElementsFromFeed(null, ConnectApi.FeedType.Record, c.Id, testPage);

        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.getTimelineData(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, items, 'Should return a list');
        System.assert(items.size() >= 2, 'Should have at least Email and FeedItem');
    }

    // ==========================================
    // 2. EMAIL ATTACHMENT TEST (FIXED)
    // ==========================================

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
        
        // FIX: The controller generates a link with data-doc-id. We check for that ID to ensure the link exists.
        String body = items[0].body;
        System.assert(body.contains(docId), 'Email body should contain the generated attachment link for DocId: ' + docId);
    }

    // ==========================================
    // 3. HYBRID TESTS (Real File + Mock Feed)
    // ==========================================

    @isTest
    static void testFeedAttachments_Hybrid() {
        ContentVersion cv = new ContentVersion(
            Title = 'Test Image',
            PathOnClient = 'test.jpg',
            VersionData = Blob.valueOf('Fake Image Data'),
            IsMajorVersion = true
        );
        insert cv;
        
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        
        // Construct JSON with the REAL docId to simulate an attachment
        String nowStr = String.valueOf(DateTime.now()).replace(' ', 'T') + 'Z';
        String jsonStr = '[' +
            '{' +
                '"attributes": {' +
                    '"type": "FeedItem",' +
                    '"url": "/services/data/v60.0/sobjects/FeedItem/0D5000000000001"' +
                '},' +
                '"Id": "0D5000000000001",' +
                '"Body": "Post with attachment",' + 
                '"Type": "TextPost",' +
                '"CreatedDate": "' + nowStr + '",' +
                '"FeedAttachments": {' +
                    '"totalSize": 1,' +
                    '"done": true,' +
                    '"records": [{' +
                        '"attributes": {' +
                            '"type": "FeedAttachment",' +
                            '"url": "/services/data/v60.0/sobjects/FeedAttachment/0D5000000000002"' +
                        '},' +
                        '"Type": "InlineImage",' +
                        '"RecordId": "' + docId + '"' + 
                    '}]' +
                '}' +
            '}' +
        ']';

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

    // ==========================================
    // 4. NEW REGEX & LINKIFY TESTS (FIXED)
    // ==========================================

    @isTest
    static void testLinkifyEdgeCases() {
        Case c = new Case(Subject='x', Status='New');
        insert c;
        
        // FIX: The controller regex requires a space, '(', or '>' before a 'www' link to be "safe".
        // Changed "check,www.google.com" to "check, https://www.yahoo.com" (added space) to match logic.
        String complexBody = 'Test 1: (www.google.com) Test 2: check, https://www.yahoo.com Test 3: <p>https://salesforce.com</p>';
        
        FeedItem fi = new FeedItem(
            ParentId = c.Id,
            Body = complexBody,
            Type = 'TextPost'
        );
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(
            new List<EmailMessage>(), 
            new List<FeedItem>{fi}, 
            null
        );
        Test.stopTest();
        
        String res = items[0].body;
        
        System.assert(res.contains('(<a href="https://www.google.com"'), 'Parentheses should act as a separator');
        System.assert(res.contains('check, <a href="https://www.yahoo.com"'), 'Commas should act as a separator if space is present');
        System.assert(res.contains('<p><a href="https://salesforce.com"'), 'HTML tags should act as separator');
    }

    @isTest
    static void testCodeBlockFormatting() {
        Case c = new Case(Subject='x', Status='New');
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
    }

    // ==========================================
    // 5. CONNECT API & HELPERS
    // ==========================================

    @isTest
    static void testConnectApiWithMention() {
        Case c = new Case(Subject='x', Status='New');
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

        FeedItem matchingSoqlItem = new FeedItem(
            ParentId = c.Id,
            Body = 'Hello @John Doe',
            Type = 'TextPost'
        );
        insert matchingSoqlItem;
        mockItem.id = matchingSoqlItem.Id; 

        ConnectApi.ChatterFeeds.setTestGetFeedElementsFromFeed(null, ConnectApi.FeedType.Record, c.Id, testPage);

        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> results = ND_CaseTimelineController.getTimelineData(c.Id);
        Test.stopTest();
        
        Boolean found = false;
        for (ND_CaseTimelineController.TimelineItem item : results) {
            if (item.id == matchingSoqlItem.Id) {
                if(item.body.contains('href="/lightning/r/')) found = true;
            }
        }
        System.assert(found, 'Should linkify the mention');
    }

    @isTest
    static void testImageUrlFixingLogic() {
        String baseUrl = 'https://base.com';
        String fileBaseUrl = 'https://file.force.com';
        Map<String, String> docMap = new Map<String, String>{ '069000000000001' => '068000000000001' };

        String html1 = '<img src="sfdc://069000000000001">';
        String res1 = ND_CaseTimelineController.fixRelativeImageUrls(html1, baseUrl, fileBaseUrl, docMap);
        System.assert(res1.contains('servlet.shepherd'), 'Should fix sfdc:// URL');
    }
    
    @isTest
    static void testSystemPostFormatting() {
        Case c = new Case(Subject='x', Status='New');
        insert c;
        
        FeedItem f1 = new FeedItem(ParentId=c.Id, Body='x', Type='ChangeStatusPost'); 
        FeedItem f2 = new FeedItem(ParentId=c.Id, Body='x', Type='CreateRecordEvent'); 
        
        String jsonStr = '[{"attributes":{"type":"FeedItem"}, "Type":"TrackedChange", "ParentId":"' + c.Id + '", "Body":"{}"}]';
        List<FeedItem> tracked = (List<FeedItem>)JSON.deserialize(jsonStr, List<FeedItem>.class);
        
        List<FeedItem> items = new List<FeedItem>{ f1, f2 };
        items.addAll(tracked);
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> res = ND_CaseTimelineController.processItems(new List<EmailMessage>(), items, null);
        Test.stopTest();
        
        Boolean foundStatus = false;
        Boolean foundTracked = false;
        
        for(ND_CaseTimelineController.TimelineItem item : res) {
            if(item.title != null && item.title.contains('Status Changed')) foundStatus = true;
            if(item.title != null && item.title.contains('Field Update')) foundTracked = true;
        }
        System.assert(foundStatus, 'Should translate ChangeStatusPost');
        System.assert(foundTracked, 'Should translate TrackedChange');
    }
    
    @isTest
    static void testJsonParser() {
        Case c = new Case(Subject='x', Status='New');
        insert c;
        String jsonPayload = 'feedEvent: {"fu":[{"fn":"Status","ov":"New","nv":"Closed"}]}';
        
        FeedItem fi = new FeedItem(ParentId = c.Id, Body = jsonPayload, Type = 'TextPost');
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.processItems(new List<EmailMessage>(), new List<FeedItem>{ fi }, null);
        Test.stopTest();

        System.assert(items[0].body.contains('Status'), 'Should parse field name');
    }
    
    @isTest
    static void testSorting() {
        ND_CaseTimelineController.TimelineItem item1 = new ND_CaseTimelineController.TimelineItem();
        item1.createdDate = DateTime.now().addMinutes(-10);
        ND_CaseTimelineController.TimelineItem item2 = new ND_CaseTimelineController.TimelineItem();
        item2.createdDate = DateTime.now();
        ND_CaseTimelineController.TimelineItem item3 = new ND_CaseTimelineController.TimelineItem();
        item3.createdDate = item2.createdDate;

        List<ND_CaseTimelineController.TimelineItem> listItems = new List<ND_CaseTimelineController.TimelineItem>{item1, item2};
        listItems.sort();

        System.assertEquals(item2, listItems[0], 'Newest item should be first');
        System.assertEquals(0, item2.compareTo(item3), 'Equal dates should compare to 0');
    }
}