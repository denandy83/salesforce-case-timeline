@isTest
public class ND_EmailCompareTest {

    @isTest
    static void testStandardEmailSplit() {
        String newReply = 'This is the new content.';
        String separator = '-----Original Message-----';
        String history = 'Old email history starts here.';
        String fullBody = newReply + '<br>' + separator + '<br>' + history;

        Test.startTest();
        ND_EmailCompare.ComparisonResult result = ND_EmailCompare.parse(fullBody, null, null, null);
        Test.stopTest();

        System.assertEquals(true, result.hasHistory, 'Should detect history separator');
        System.assert(result.newContent.contains(newReply), 'New content should be extracted');
        System.assert(!result.newContent.contains(history), 'New content should not contain history');
    }

    @isTest
    static void testOutlookHeaderSplit() {
        String newReply = 'Thanks for the update.';
        // Simulate "On [Date] [Name] wrote:" pattern
        String history = 'On Mon, Dec 1, 2025 at 10:00 AM John Doe wrote:<br>Previous message';
        String fullBody = newReply + '<br><br>' + history;

        Test.startTest();
        ND_EmailCompare.ComparisonResult result = ND_EmailCompare.parse(fullBody, null, null, null);
        Test.stopTest();

        System.assertEquals(true, result.hasHistory, 'Should detect "On... wrote:" pattern');
        System.assert(result.newContent.contains('Thanks'), 'Should keep new reply');
    }

    @isTest
    static void testGmailQuoteSplit() {
        String newReply = 'Replying from Gmail.';
        String fullBody = newReply + '<div class="gmail_quote">On Mon, Dec 1...</div>';

        Test.startTest();
        ND_EmailCompare.ComparisonResult result = ND_EmailCompare.parse(fullBody, null, null, null);
        Test.stopTest();

        System.assertEquals(true, result.hasHistory, 'Should detect gmail_quote class');
        System.assert(!result.newContent.contains('gmail_quote'), 'New content should strip quote div');
    }

    @isTest
    static void testClutterRemoval() {
        String dirtyHtml = '<html><head><style>body {color:red;}</style></head>' + 
                           '<body>Real Content<script>alert("hack");</script></body></html>';
        
        Test.startTest();
        ND_EmailCompare.ComparisonResult result = ND_EmailCompare.parse(dirtyHtml, null, null, null);
        Test.stopTest();

        System.assert(!result.newContent.contains('<style>'), 'Should remove style tags');
        System.assert(!result.newContent.contains('<script>'), 'Should remove script tags');
        System.assert(result.newContent.contains('Real Content'), 'Should keep content');
    }

    @isTest
    static void testCharacterLimitTruncation() {
        // Generate a string longer than 1950 chars
        String longText = 'A'.repeat(2500);
        String htmlBody = '<p>' + longText + '</p>';

        Test.startTest();
        ND_EmailCompare.ComparisonResult result = ND_EmailCompare.parse(htmlBody, null, null, null);
        Test.stopTest();

        // The visible text limit is 1950
        System.assert(result.newContent.length() < 2500, 'Content should be truncated');
        System.assertEquals(true, result.hasHistory, 'Should flag as having history/more content due to truncation');
        System.assert(result.historyContent.length() > 0, 'Overflow should move to history');
    }

    @isTest
    static void testFlowInvocable() {
        ND_EmailCompare.FlowInput input = new ND_EmailCompare.FlowInput();
        input.currentHtml = 'Flow Test<br>-----Original Message-----<br>History';
        input.currentText = 'Flow Test\n-----Original Message-----\nHistory';

        List<ND_EmailCompare.FlowInput> inputs = new List<ND_EmailCompare.FlowInput>{ input };

        Test.startTest();
        List<ND_EmailCompare.ComparisonResult> results = ND_EmailCompare.parseForFlow(inputs);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].hasHistory);
        System.assertEquals('Flow Test', results[0].newContentPlain.trim());
    }

    @isTest
    static void testTextOnlyFallback() {
        // Provide only text body, no HTML
        String textBody = 'Plain text reply\n____________________\nOld text';
        
        Test.startTest();
        ND_EmailCompare.ComparisonResult result = ND_EmailCompare.parse(null, textBody, null, null);
        Test.stopTest();

        System.assertEquals(true, result.hasHistory, 'Should split on underscores in plain text');
        System.assert(result.newContent.contains('Plain text reply'));
        // Parser converts newlines to breaks for HTML view
        System.assert(result.newContent.contains('<br/>')); 
    }
}