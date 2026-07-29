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
        
        Contact con = new Contact(FirstName = 'Test', LastName = 'TestContact', Email = 'test0@example.com', AVB_Role__c = 'Administrator');
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

        FeedItem fi = [SELECT Id FROM FeedItem LIMIT 1];
        ND_CaseTimelineController.addComment(fi.Id, 'Test comment');
        ND_CaseTimelineController.addComment(null, null);

        ND_CaseTimelineController.getTimelineCounts(c.Id);
        ND_CaseTimelineController.getTimelineCounts(null);
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
    static void testRobustHistoryDetection() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        
        // Body with "From:" and "wrote:" that should NOT trigger truncation (inline text)
        String safeBody = '<html><body>' +
            'This is a normal sentence. From: someone@test.com and he wrote: "something". ' +
            'This should not be truncated by the history detection because it is just text. ' +
            '</body></html>';
            
        EmailMessage em = new EmailMessage(
            ParentId = c.Id, Subject = 'Safe Test', HtmlBody = safeBody, TextBody = 'fallback',
            MessageDate = DateTime.now(), Incoming = true,
            FromAddress = 'test@test.com', FromName = 'Test',
            ToAddress = 'to@test.com', Status = '1'
        );
        insert em;
        
        Test.startTest();
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.getTimelineData(c.Id, null, 20, 'desc', false, null);
        Test.stopTest();
        
        // Find the item for the test email
        ND_CaseTimelineController.TimelineItem foundItem;
        for (ND_CaseTimelineController.TimelineItem item : items) {
            if (item.emailSubject == 'Safe Test') {
                foundItem = item;
                break;
            }
        }
        
        System.assertNotEquals(null, foundItem, 'Test email should be found');
        System.assertEquals(false, foundItem.hasHistory, 'Safe email should not have history detected');
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
    static void testLargeEmailHandling() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        // Build a body > 15KB with various history markers embedded
        String padding = '';
        for (Integer i = 0; i < 200; i++) {
            padding += '<p>Line ' + i + ' of padding content for large email test. This adds length to the body.</p>';
        }
        // Body with "From:" + "Sent:" pattern deep inside
        String largeBody = '<html><body>' + padding +
            '<b>From:</b> someone@test.com<br/><b>Sent:</b> Monday, Jan 1<br/>' +
            padding + '</body></html>';

        // Body with "--- Original Message" marker
        String bodyWithMarker = '<html><body>' + padding +
            '--------------- Original Message ---------------<br/>' +
            '<b>From:</b> old@test.com<br/>' + '</body></html>';

        // Body with "On ... wrote:" pattern
        String bodyWithWrote = '<html><body>' + padding +
            'On Mon, Jan 1 2026 someone@test.com wrote: previous reply' + '</body></html>';

        // Body with French pattern
        String bodyFrench = '<html><body>' + padding +
            'De: utilisateur@test.com Envoy le lundi' + '</body></html>';

        // Body with Italian pattern
        String bodyItalian = '<html><body>' + padding +
            'Da: utente@test.com Inviato lunedi' + '</body></html>';

        // Body with underscores
        String bodyUnderscores = '<html><body>' + padding +
            '________________________' + padding + '</body></html>';

        List<EmailMessage> ems = new List<EmailMessage>();
        for (String b : new List<String>{largeBody, bodyWithMarker, bodyWithWrote, bodyFrench, bodyItalian, bodyUnderscores}) {
            ems.add(new EmailMessage(
                ParentId = c.Id, Subject = 'Large Test', HtmlBody = b, TextBody = 'fallback',
                MessageDate = DateTime.now(), Incoming = true,
                FromAddress = 'large@test.com', FromName = 'Large Sender',
                ToAddress = 'to@test.com', Status = '1'
            ));
        }
        insert ems;

        Test.startTest();
        // Exercises findHistorySplit (anchor pre-scan + indexOf), O(n) image processing, and getEmailHistory
        List<ND_CaseTimelineController.TimelineItem> items = ND_CaseTimelineController.getTimelineData(c.Id, null, 20, 'desc', false, null);
        System.assert(items.size() > 0, 'Should return items');

        // Large emails must render a real body — no red placeholder regardless of size
        for (ND_CaseTimelineController.TimelineItem item : items) {
            if (item.category == 'Email') {
                System.assert(!item.body.contains('Long email'), 'Large emails should render body content, not a placeholder: ' + item.title);
                System.assert(String.isNotBlank(item.body), 'Email body should not be blank: ' + item.title);
            }
        }

        // Test getEmailHistory on a large email (exercises full-body return + chunking)
        ND_CaseTimelineController.getEmailHistory(ems[0].Id);
        ND_CaseTimelineController.getEmailHistory(ems[1].Id);
        Test.stopTest();
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

    /**
     * Regression guard for the inline-image id scan. Two bugs meet here:
     *
     *  1. EMPTY TIMELINE — a body-wide id regex scraped '069a082b954e687b5a' out of the MIDDLE
     *     of a 64-char SHA-256 checksum in a forwarded email. Fed into
     *     `ContentVersion WHERE ContentDocumentId IN :ids` it raised an UNCATCHABLE
     *     "Unable to Access Page" for restricted profiles (AVB_Service), aborting
     *     getTimelineData -> blank timeline. Admins were unaffected (they get 0 rows).
     *
     *  2. MISSING SCREENSHOTS — the fix for (1) whitelisted only ids linked to the case's
     *     emails/feed items. Chatter rich-text inline images are ContentDocumentLink'd to the
     *     CASE, never to the FeedItem, so every inline screenshot was silently dropped.
     *
     * Do NOT "simplify" getUsedInlineIds back to scanning the whole body — that is bug (1).
     */
    @isTest
    static void testInlineIdExtractionIsContextScoped() {
        String hashOnly = '<div>Checksum: 9302d10b714dc0069a082b954e687b5a392622d156479d3e6f479ef4be3057fc</div>';
        String chatterImg = '<p><img src="sfdc://069TX00000a8a81YAA" alt="Greenshot"></img></p>';

        // (1) a checksum in free text must never be treated as a file id
        System.assert(
            ND_CaseTimelineController.getUsedInlineIds(hashOnly).isEmpty(),
            'A SHA-256 fragment in body text must not be scraped as a ContentDocumentId'
        );

        // (2) a Chatter rich-text inline image must still be found
        System.assert(
            ND_CaseTimelineController.getUsedInlineIds(chatterImg).contains('069TX00000a8a81YAA'),
            'sfdc:// inline image id must be extracted'
        );

        // (3) both together: the image survives, the checksum does not
        Set<String> mixed = ND_CaseTimelineController.getUsedInlineIds(hashOnly + chatterImg);
        System.assert(mixed.contains('069TX00000a8a81YAA'), 'Real inline image must survive');
        System.assert(!mixed.contains('069a082b954e687b5a'), 'Checksum fragment must be filtered out');

        // (4) email inline formats still recognised
        Set<String> rendition = ND_CaseTimelineController.getUsedInlineIds(
            '<img src="https://x.file.force.com/sfc/servlet.shepherd/version/renditionDownload' +
            '?rendition=THUMB720BY480&versionId=068TX00000aFqXpYAK&contentId=069TX00000a8a81YAA">'
        );
        System.assert(rendition.contains('068TX00000aFqXpYAK'), 'Version id must be extracted');
        System.assert(rendition.contains('069TX00000a8a81YAA'), 'Document id must be extracted');
        System.assert(
            ND_CaseTimelineController.getUsedInlineIds(
                '<img src="/servlet/servlet.FileDownload?file=00P000000000001">'
            ).contains('00P000000000001'),
            'Legacy Attachment servlet id must be extracted'
        );

        // (5) the id-checksum net: malformed 18-char ids are rejected, real ids accepted
        System.assertEquals(false, ND_CaseTimelineController.isValidFileId('069a082b954e687b5a'),
            'Malformed 18-char id must fail the checksum');
        System.assertEquals(true, ND_CaseTimelineController.isValidFileId('069TX00000a8a81YAA'),
            'Real 18-char ContentDocumentId must validate');
        System.assertEquals(false, ND_CaseTimelineController.isValidFileId(null), 'Null is not an id');
        System.assertEquals(false, ND_CaseTimelineController.isValidFileId(''), 'Blank is not an id');

        // (6) no file references at all -> nothing extracted
        System.assert(
            ND_CaseTimelineController.getUsedInlineIds('<p>plain text, no images</p>').isEmpty(),
            'A body with no file references yields no ids'
        );
        System.assert(ND_CaseTimelineController.getUsedInlineIds(null).isEmpty(), 'Null body is safe');
    }
}