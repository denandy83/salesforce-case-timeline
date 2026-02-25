@isTest
public class ND_TimelineTest_Final {

    @testSetup
    static void setupData() {
        Case c = new Case(Subject = 'Test Case Timeline', Status = 'New');
        insert c;

        List<EmailMessage> ems = new List<EmailMessage>();
        for (Integer i = 0; i < 5; i++) {
            ems.add(new EmailMessage(
                ParentId = c.Id,
                Subject = 'Test Email ' + i,
                HtmlBody = '<html><body>Test Body ' + i + ' 069000000000001 <br/>--------------- Original Message ---------------<br/> History content <img src="sfdc://069000000000001"></body></html>',
                TextBody = 'Text Body \\n Line 2',
                CcAddress = 'cc' + i + '@test.com',
                BccAddress = 'bcc' + i + '@test.com',
                MessageDate = DateTime.now().addMinutes(-i),
                Incoming = true,
                FromAddress = 'test' + i + '@example.com',
                FromName = 'Test Sender ' + i,
                ToAddress = 'test@test.com',
                Status = '1'
            ));
        }
        insert ems;

        List<FeedItem> fis = new List<FeedItem>();
        fis.add(new FeedItem(ParentId = c.Id, Body = 'Text Post @[Test User]', Type = 'TextPost', Visibility = 'AllUsers'));
        fis.add(new FeedItem(ParentId = c.Id, Body = 'Link Post https://test.com', Type = 'LinkPost', Title = 'Test Link', LinkUrl = 'https://test.com'));
        insert fis;
        
        FeedComment fc = new FeedComment(FeedItemId = fis[0].Id, CommentBody = 'Comment 069000000000001');
        insert fc;

        ContentVersion cv = new ContentVersion(Title = 'File', PathOnClient = 'File.jpg', VersionData = Blob.valueOf('Data'), IsMajorVersion = true);
        insert cv;
        Id conDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        
        ContentDocumentLink cdl = new ContentDocumentLink(LinkedEntityId = ems[0].Id, ContentDocumentId = conDocId, ShareType = 'V');
        insert cdl;

        Attachment legAtt = new Attachment(ParentId = ems[0].Id, Name = 'Leg.txt', Body = Blob.valueOf('C'));
        insert legAtt;
        
        Contact con = new Contact(LastName = 'TestContact', Email = 'test0@example.com');
        insert con;
    }

    @isTest
    static void testGetTimelineDataFullCoverage() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        EmailMessage em = [SELECT Id, MessageDate FROM EmailMessage LIMIT 1];
        Test.startTest();
        ND_CaseTimelineController.getTimelineData(c.Id, null, 20, 'desc', true, null);
        ND_CaseTimelineController.getTimelineData(c.Id, em.MessageDate, 5, 'desc', true, em.Id);
        ND_CaseTimelineController.getTimelineData(c.Id, em.MessageDate, 5, 'asc', true, em.Id);
        Test.stopTest();
    }

    @isTest
    static void testHelpers() {
        EmailMessage em = [SELECT Id FROM EmailMessage LIMIT 1];
        ND_CaseTimelineController.getEmailHistory(em.Id);
        ND_CaseTimelineController.getEmailHistory(null);
        
        ND_CaseTimelineController.formatSystemTitle('TrackedChange');
        ND_CaseTimelineController.formatSystemTitle('CreateRecordEvent');
        ND_CaseTimelineController.formatSystemTitle('ChangeStatusPost');
        ND_CaseTimelineController.formatSystemTitle('ActivityEvent');
        
        Case c = [SELECT Id FROM Case LIMIT 1];
        ND_CaseTimelineController.checkForNewItems(c.Id, DateTime.now().addDays(-1));
        ND_CaseTimelineController.checkForNewItems(null, null);
        
        Map<String,String> m = new Map<String,String>{'New'=>'New'};
        ND_CaseTimelineController.parseFeedEventString('{"fu":[{"fn":"Status","ov":"Old","nv":"New"}]}', m);
        ND_CaseTimelineController.parseFeedEventString('invalid', m);
        
        Map<String, String> docMap = new Map<String,String>{'069000000000001' => '068000000000001'};
        ND_CaseTimelineController.fixRelativeImageUrls('<img src="sfdc://069000000000001">', 'b', 'f', docMap, null);
        ND_CaseTimelineController.fixRelativeImageUrls('<img src="https://my.salesforce.com/test">', 'b', 'f', docMap, null);
        ND_CaseTimelineController.fixRelativeImageUrls('<img src="cid:test">', 'b', 'f', docMap, new List<Attachment>{new Attachment(Name='a', Body=Blob.valueOf('x'))});
        ND_CaseTimelineController.fixRelativeImageUrls('<img src="/test">', 'b', 'f', docMap, null);
        
        ND_CaseTimelineController.makeImagesClickable('<img src="contentId=069000000000001">', docMap);
        ND_CaseTimelineController.makeImagesClickable('<img src="versionId=068000000000001">', docMap);
        ND_CaseTimelineController.makeImagesClickable('<img src="/version/download/068000000000001">', docMap);
        ND_CaseTimelineController.makeImagesClickable('<img src="file=00P000000000001">', docMap);
        ND_CaseTimelineController.makeImagesClickable(null, null);
    }

    @isTest
    static void testSorting() {
        EmailMessage em = [SELECT Id, MessageDate FROM EmailMessage LIMIT 1];
        ND_CaseTimelineController.RawItemWrapper w1 = new ND_CaseTimelineController.RawItemWrapper(em, 'desc');
        ND_CaseTimelineController.RawItemWrapper w2 = new ND_CaseTimelineController.RawItemWrapper(em, 'desc');
        w1.compareTo(w2);
        w1.sortDir = 'asc';
        w1.compareTo(w2);
    }

    @isTest
    static void testCountsAndComment() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        ND_CaseTimelineController.getTimelineCounts(c.Id);
        FeedItem fi = [SELECT Id FROM FeedItem LIMIT 1];
        ND_CaseTimelineController.addComment(fi.Id, 'Test');
    }
    
    @isTest
    static void testInnerClasses() {
        new ND_CaseTimelineController.TimelineConfig();
        ND_CaseTimelineController.getTimelineConfig();
        new ND_CaseTimelineController.CommentItem('a','b','c',DateTime.now());
        ND_CaseTimelineController.TimelineItem ti = new ND_CaseTimelineController.TimelineItem();
        ti.createdDate = DateTime.now();
        ti.sortDir = 'desc';
        ti.compareTo(ti);
    }

    @isTest
    static void testFileOverview() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        
        // Setup another file with same content (duplicate)
        ContentVersion cv2 = new ContentVersion(Title = 'File Duplicate', PathOnClient = 'File2.jpg', VersionData = Blob.valueOf('Data'), IsMajorVersion = true);
        insert cv2;
        Id conDocId2 = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv2.Id].ContentDocumentId;
        ContentDocumentLink cdl2 = new ContentDocumentLink(LinkedEntityId = c.Id, ContentDocumentId = conDocId2, ShareType = 'V');
        insert cdl2;

        Test.startTest();
        // Test basic fetch
        List<ND_CaseTimelineController.FileItem> files = ND_CaseTimelineController.getFiles(c.Id, 50, 0, null, 'createdDate', 'desc', false);
        
        // Test search
        List<ND_CaseTimelineController.FileItem> searchFiles = ND_CaseTimelineController.getFiles(c.Id, 50, 0, 'File', 'fullName', 'asc', false);
        
        // Test deduplication
        List<ND_CaseTimelineController.FileItem> uniqueFiles = ND_CaseTimelineController.getFiles(c.Id, 50, 0, null, 'size', 'desc', true);
        
        // Test other sort fields
        ND_CaseTimelineController.getFiles(c.Id, 10, 0, null, 'fileType', 'asc', false);
        ND_CaseTimelineController.getFiles(c.Id, 10, 0, null, 'ownerName', 'asc', false);
        
        // Test null case
        ND_CaseTimelineController.getFiles(null, 10, 0, null, null, null, false);
        Test.stopTest();
        
        System.assertNotEquals(0, files.size(), 'Should have returned files');
    }
}
