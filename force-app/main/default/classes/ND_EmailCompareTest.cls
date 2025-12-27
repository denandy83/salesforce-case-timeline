@isTest
public class ND_EmailCompareTest {

    @isTest
    static void testParseForFlow_StandardHeaders() {
        // 1. Setup Input: "From:" Header
        ND_EmailCompare.FlowInput input1 = new ND_EmailCompare.FlowInput();
        input1.currentText = 'This is new content.\n\nFrom: Old Sender\nSent: Yesterday\nOld content...';
        input1.characterLimit = 5000; // Large limit, relying on regex

        // 2. Setup Input: "On ... wrote:" Header
        ND_EmailCompare.FlowInput input2 = new ND_EmailCompare.FlowInput();
        input2.currentText = 'New reply text.\nOn Mon, Jan 1, 2024 at 10:00 AM wrote:\n> Old message';
        input2.characterLimit = 5000;

        // 3. Setup Input: "Original Message" Header
        ND_EmailCompare.FlowInput input3 = new ND_EmailCompare.FlowInput();
        input3.currentText = 'Top message.\n-----Original Message-----\nBottom message';
        input3.characterLimit = 5000;

        List<ND_EmailCompare.FlowInput> inputs = new List<ND_EmailCompare.FlowInput>{input1, input2, input3};

        Test.startTest();
        List<ND_EmailCompare.ComparisonResult> results = ND_EmailCompare.parseForFlow(inputs);
        Test.stopTest();

        // Assertions
        System.assertEquals(3, results.size());
        
        // Check input 1
        System.assertEquals('This is new content.\n\n', results[0].newContentPlain, 'Should cut before "From:"');
        
        // Check input 2
        System.assertEquals('New reply text.\n', results[1].newContentPlain, 'Should cut before "On ... wrote:"');
        
        // Check input 3
        System.assertEquals('Top message.\n', results[2].newContentPlain, 'Should cut before "Original Message"');
    }

    @isTest
    static void testParseForFlow_CharacterLimit() {
        // Setup Input: Long text, no headers
        ND_EmailCompare.FlowInput input = new ND_EmailCompare.FlowInput();
        String longText = '1234567890'; // 10 chars
        input.currentText = longText;
        input.characterLimit = 5; // Cut at 5

        List<ND_EmailCompare.FlowInput> inputs = new List<ND_EmailCompare.FlowInput>{input};

        Test.startTest();
        List<ND_EmailCompare.ComparisonResult> results = ND_EmailCompare.parseForFlow(inputs);
        Test.stopTest();

        System.assertEquals('12345', results[0].newContentPlain, 'Should truncate at character limit');
    }

    @isTest
    static void testParseForFlow_HeaderBeforeLimit() {
        // Setup Input: Header appears at char 10. Limit is 50.
        ND_EmailCompare.FlowInput input = new ND_EmailCompare.FlowInput();
        // FIXED: Added "Sent: Date" so the Regex recognizes it as a valid header
        input.currentText = 'New text.\nFrom: Old Text\nSent: Monday'; 
        input.characterLimit = 50; 

        List<ND_EmailCompare.FlowInput> inputs = new List<ND_EmailCompare.FlowInput>{input};

        Test.startTest();
        List<ND_EmailCompare.ComparisonResult> results = ND_EmailCompare.parseForFlow(inputs);
        Test.stopTest();

        // The expected result should be just "New text.\n"
        System.assertEquals('New text.\n', results[0].newContentPlain, 'Should cut at Header because it appears before limit');
    }

    @isTest
    static void testParseForFlow_LimitBeforeHeader() {
        // Setup Input: Header appears at char 50. Limit is 5.
        // Should cut at Limit (earlier).
        ND_EmailCompare.FlowInput input = new ND_EmailCompare.FlowInput();
        input.currentText = '1234567890\nFrom: Old Text'; 
        input.characterLimit = 5; 

        List<ND_EmailCompare.FlowInput> inputs = new List<ND_EmailCompare.FlowInput>{input};

        Test.startTest();
        List<ND_EmailCompare.ComparisonResult> results = ND_EmailCompare.parseForFlow(inputs);
        Test.stopTest();

        System.assertEquals('12345', results[0].newContentPlain, 'Should cut at Limit because it is smaller than split index');
    }

    @isTest
    static void testParseForFlow_NullAndEmpty() {
        ND_EmailCompare.FlowInput input1 = new ND_EmailCompare.FlowInput();
        input1.currentText = null;

        ND_EmailCompare.FlowInput input2 = new ND_EmailCompare.FlowInput();
        input2.currentText = '';

        List<ND_EmailCompare.FlowInput> inputs = new List<ND_EmailCompare.FlowInput>{input1, input2};

        Test.startTest();
        List<ND_EmailCompare.ComparisonResult> results = ND_EmailCompare.parseForFlow(inputs);
        Test.stopTest();

        System.assertEquals('', results[0].newContentPlain);
        System.assertEquals('', results[1].newContentPlain);
    }
}