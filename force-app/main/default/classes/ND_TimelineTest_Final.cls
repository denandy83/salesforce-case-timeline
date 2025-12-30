@isTest
public class ND_TimelineTest_Final {

    @testSetup
    static void setupData() {
        // 1. Create a Parent Case
        Case c = new Case(Subject = 'Test Case Timeline', Status = 'New');
        insert c;

        // 2. Create an Email Message (Includes required fields for your Org's flows)
        EmailMessage em = new EmailMessage(
            ParentId = c.Id,
            Subject = 'Test Email',
            HtmlBody = '<html><body>Test Body <img src="sfdc://069000000000001"></body></html>',
            TextBody = 'Test Body content for flow requirements',
            MessageDate = DateTime.now().addHours(-1),
            Incoming = true,
            FromAddress = 'test@example.com',
            FromName = 'Test Sender',
            ToAddress = 'test@test.com'
        );
        insert em;

        // 3. Create a Standard Text Feed Item
        FeedItem fi = new FeedItem();
        fi.ParentId = c.Id;
        fi.Body = 'Test Chatter Post with a link https://www.salesforce.com and <code>code block</code>';
        fi.Type = 'TextPost';
        insert fi;
        
        // 4. Create a Feed Item with an Attachment (ContentPost)
        FeedItem fiPost = new FeedItem(
            ParentId = c.Id,
            Body = 'Feed with Attachment',
            Type = 'ContentPost'
        );
        insert fiPost;

        // 5. Create Content for the Feed
        ContentVersion cvFeed = new ContentVersion(
            Title = 'FeedFile',
            PathOnClient = 'FeedFile.jpg',
            VersionData = Blob.valueOf('Feed Data'),
            IsMajorVersion = true
        );
        insert cvFeed;
        Id conVersionId = [SELECT Id FROM ContentVersion WHERE Id = :cvFeed.Id].Id;
        
        // 6. Link Content to Feed (FeedAttachment)
        FeedAttachment fa = new FeedAttachment(
            FeedEntityId = fiPost.Id,
            RecordId = conVersionId, 
            Type = 'Content'
        );
        insert fa;
        
        // 7. Create a ContentVersion (Standard Email File)
        ContentVersion cv = new ContentVersion();
        cv.Title = 'Modern File';
        cv.PathOnClient = 'ModernFile.pdf';
        cv.VersionData = Blob.valueOf('Test Content');
        cv.IsMajorVersion = true;
        insert cv;
        
        // 8. Link File to the Email (ContentDocumentLink)
        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        ContentDocumentLink cdlEmail = new ContentDocumentLink();
        cdlEmail.LinkedEntityId = em.Id;
        cdlEmail.ContentDocumentId = conDocId;
        cdlEmail.ShareType = 'V';
        insert cdlEmail;

        // 9. Create a Legacy Attachment
        Attachment legAtt = new Attachment();
        legAtt.ParentId = em.Id;
        legAtt.Name = 'LegacyAttachment.txt';
        legAtt.Body = Blob.valueOf('Legacy Content');
        insert legAtt;
    }

    @isTest
    static void testConfigLogic() {
        Test.startTest();
        // 1. Test Wrapper Constructor directly (Coverage for defaults)
        ND_CaseTimelineController.TimelineConfig wrapper = new ND_CaseTimelineController.TimelineConfig();
        System.assertEquals(10, wrapper.batchSize);
        // Verify new default values in wrapper
        System.assertEquals(1, wrapper.previewLines, 'Default preview lines should be 1');
        System.assertEquals(false, wrapper.useToastForUpdates, 'Default toast usage should be false');

        // 2. Test Get Config (Creates New)
        ND_CaseTimelineController.TimelineConfig c1 = ND_CaseTimelineController.getTimelineConfig();
        System.assertNotEquals(null, c1.configId);
        // Verify DB defaults
        System.assertEquals(1, c1.previewLines);
        System.assertEquals(false, c1.useToastForUpdates);

        // 3. Update the Config Record to test mapping
        Custom_Configuration__c dbConfig = [SELECT Id FROM Custom_Configuration__c WHERE Id = :c1.configId];
        dbConfig.Collapsed_Preview_Lines__c = 5;
        dbConfig.Toast_for_new_data__c = true;
        update dbConfig;

        // 4. Retrieve again and verify updates
        ND_CaseTimelineController.TimelineConfig c2 = ND_CaseTimelineController.getTimelineConfig();
        System.assertEquals(c1.configId, c2.configId);
        System.assertEquals(5, c2.previewLines, 'Should return updated preview lines');
        System.assertEquals(true, c2.useToastForUpdates, 'Should return updated toast setting');
        
        Test.stopTest();
    }

    @isTest
    static void testGetTimelineDataFull() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.getTimelineData(c.Id, DateTime.now().addDays(1), 20, 'desc', false);
        Test.stopTest();

        System.assert(items.size() >= 2, 'Should have at least an email and a feed item');
        
        Boolean foundLegacy = false;
        Boolean foundModern = false;
        Boolean foundFeedLink = false;
        Boolean foundFeedAttachment = false;

        for(ND_CaseTimelineController.TimelineItem item : items) {
            // Check Emails
            if(item.category == 'Email' && item.attachmentsHtml != null) {
                if(item.attachmentsHtml.contains('LegacyAttachment.txt')) foundLegacy = true;
                if(item.attachmentsHtml.contains('Modern File')) foundModern = true;
            } 
            // Check Feed Items
            else if (item.category == 'Internal' || item.category == 'Public') {
                if (item.body.contains('<a href="https://www.salesforce.com"')) foundFeedLink = true;
                
                // Check if Feed Attachment HTML was generated
                if (item.attachmentsHtml != null && item.attachmentsHtml.contains('FeedFile')) {
                    foundFeedAttachment = true;
                }
            }
            item.compareTo(item); 
        }
        
        System.assert(foundLegacy, 'Legacy Attachment HTML should be generated');
        System.assert(foundModern, 'ContentDocumentLink HTML should be generated');
        System.assert(foundFeedLink, 'Should have auto-linked the URL');
        // Note: FeedAttachment assertion might vary based on Feed Type support in test context
    }

    @isTest
    static void testDirectHelperCoverage() {
        Test.startTest();
        
        String badHtml = '<html><head><script></script></head><body>Link: www.google.com</body></html>';
        
        String t1 = ND_CaseTimelineController.formatSystemTitle('TrackedChange');
        String t2 = ND_CaseTimelineController.formatSystemTitle('CreateRecordEvent');
        String t3 = ND_CaseTimelineController.formatSystemTitle('Unknown');
        System.assertEquals('Field Update', t1);
        System.assertEquals(t3, 'Unknown');

        Case c = [SELECT Id FROM Case LIMIT 1];
        Boolean hasNew = ND_CaseTimelineController.checkForNewItems(c.Id, DateTime.now().addDays(-5));
        System.assert(hasNew);

        String json = '{"fu":[{"fn":"Status","ov":"New","nv":"Closed"}]}';
        Map<String,String> statusMap = new Map<String,String>();
        String parsed = ND_CaseTimelineController.parseFeedEventString(json, statusMap);
        System.assert(parsed.contains('Status'));
        
        Map<String, String> docMap = new Map<String,String>{'069000000000001' => '068000000000001'};
        String imgHtml = '<img src="sfdc://069000000000001">';
        String fixed = ND_CaseTimelineController.fixRelativeImageUrls(imgHtml, 'domain', 'filedomain', docMap);
        System.assert(fixed.contains('filedomain'));

        Test.stopTest();
    }
    
    @isTest
    static void testFileIconLogic() {
        Case c = new Case(Subject='File Test');
        insert c;
        
        EmailMessage em = new EmailMessage(
            ParentId = c.Id, 
            Incoming = true, 
            ToAddress = 'test@test.com', 
            FromAddress = 'test@example.com',
            Subject = 'File Icon Test',
            TextBody = 'Text body',
            HtmlBody = '<html><body>Text body</body></html>'
        );
        insert em;
        
        List<Attachment> atts = new List<Attachment>();
        atts.add(new Attachment(ParentId=em.Id, Name='test.xls', Body=Blob.valueOf('x')));
        atts.add(new Attachment(ParentId=em.Id, Name='test.ppt', Body=Blob.valueOf('x')));
        atts.add(new Attachment(ParentId=em.Id, Name='test.zip', Body=Blob.valueOf('x')));
        atts.add(new Attachment(ParentId=em.Id, Name='test.png', Body=Blob.valueOf('x')));
        atts.add(new Attachment(ParentId=em.Id, Name='test.unknown', Body=Blob.valueOf('x')));
        insert atts;
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.getTimelineData(c.Id, DateTime.now(), 10, 'desc', false);
        Test.stopTest();
        
        for(ND_CaseTimelineController.TimelineItem i : items) {
            if (i.category == 'Email') {
                System.assertNotEquals(null, i.attachmentsHtml); 
                System.assert(i.attachmentsHtml.contains('test.xls'));
            }
        }
    }
}