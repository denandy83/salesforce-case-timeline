@isTest
public class ND_EmailCompareTest {

    @isTest
    static void testStandardParseLogic() {
        // 1. Define inputs
        String newReply = 'This is a new reply.';
        String history = '-----Original Message----- Old email content.';
        String fullBody = newReply + '<br>' + history;

        // 2. Call the method directly
        ND_EmailCompare.ComparisonResult res = ND_EmailCompare.parse(fullBody, null, null, null);

        // 3. Assertions
        System.assertEquals(true, res.hasHistory, 'Should detect history separator');
        System.assert(res.newContent.contains(newReply), 'New content should be extracted');
        System.assert(res.historyContent.contains('Original Message'), 'History content should contain the separator');
    }

    @isTest
    static void testNoHistory() {
        // Test case where there is NO separator
        String simpleBody = 'Just a simple email with no history.';
        
        ND_EmailCompare.ComparisonResult res = ND_EmailCompare.parse(simpleBody, null, null, null);

        System.assertEquals(false, res.hasHistory, 'Should NOT detect history');
        System.assertEquals(simpleBody, res.newContent, 'New content should match full body');
        System.assertEquals('', res.historyContent, 'History should be empty');
    }

    @isTest
    static void testFlowMethod() {
        // 1. Prepare Flow Input Wrapper
        ND_EmailCompare.FlowInput input = new ND_EmailCompare.FlowInput();
        input.currentHtml = 'Flow Reply <div class="gmail_quote">Old Gmail Stuff</div>';
        
        // Flow methods accept a List and return a List
        List<ND_EmailCompare.FlowInput> inputList = new List<ND_EmailCompare.FlowInput>();
        inputList.add(input);

        // 2. Call the Invocable Method
        Test.startTest();
        List<ND_EmailCompare.ComparisonResult> results = ND_EmailCompare.parseForFlow(inputList);
        Test.stopTest();

        // 3. Assertions
        System.assertNotEquals(null, results, 'Flow result list should not be null');
        System.assertEquals(1, results.size(), 'Should return 1 result');
        
        ND_EmailCompare.ComparisonResult res = results[0];
        System.assertEquals(true, res.hasHistory, 'Flow should detect Gmail history');
        System.assert(res.newContent.contains('Flow Reply'), 'Flow should return correct new content');
    }

    @isTest
    static void testTextOnlyFallback() {
        // Test providing TextBody instead of HtmlBody
        String textBody = 'Text Reply\n-----Original Message-----\nOld Text';
        
        ND_EmailCompare.ComparisonResult res = ND_EmailCompare.parse(null, textBody, null, null);

        // The parser converts \n to <br/>, so we check for that
        System.assert(res.newContent.contains('Text Reply'), 'Should handle text body input');
        System.assertEquals(true, res.hasHistory, 'Should find separator in text body');
    }
}