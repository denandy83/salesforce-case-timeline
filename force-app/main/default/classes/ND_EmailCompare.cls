public with sharing class ND_EmailCompare {

    // ==========================================
    // 1. FLOW INPUT WRAPPER (New - For Flow Only)
    // ==========================================
    public class FlowInput {
        @InvocableVariable(label='Current HTML Body' required=false)
        public String currentHtml;

        @InvocableVariable(label='Current Text Body' required=false)
        public String currentText;

        @InvocableVariable(label='Previous HTML Body' required=false)
        public String previousHtml;

        @InvocableVariable(label='Previous Text Body' required=false)
        public String previousText;
    }

    // ==========================================
    // 2. OUTPUT RESULT (Updated with Annotations)
    // ==========================================
    public class ComparisonResult {
        // We add @InvocableVariable so Flow can see these.
        // We add @AuraEnabled so LWC can see them (if needed in future).
        // Standard Apex can still read them because they are 'public'.
        @InvocableVariable @AuraEnabled public String newContent;      
        @InvocableVariable @AuraEnabled public String historyContent;  
        @InvocableVariable @AuraEnabled public Boolean hasHistory;     
    }

    // ==========================================
    // 3. INVOCABLE METHOD (New - For Flow Only)
    // ==========================================
    @InvocableMethod(label='ND_Email Compare' description='Splits email body into New Content and History' category='Email')
    public static List<ComparisonResult> parseForFlow(List<FlowInput> inputs) {
        List<ComparisonResult> results = new List<ComparisonResult>();
        
        // Loop through flow inputs and call the main logic
        for (FlowInput input : inputs) {
            results.add(parse(input.currentHtml, input.currentText, input.previousHtml, input.previousText));
        }
        return results;
    }

    // ==========================================
    // 4. MAIN LOGIC (Unchanged - Used by Timeline)
    // ==========================================
    public static ComparisonResult parse(String currentHtml, String currentText, String previousHtml, String previousText) {
        ComparisonResult res = new ComparisonResult();
        
        // 1. Get the HTML Body
        String fullBody = '';
        if (String.isNotBlank(currentHtml)) {
            fullBody = currentHtml;
        } else if (String.isNotBlank(currentText)) {
            fullBody = currentText.replace('\n', '<br/>');
        }

        // 2. Prepare for Matching
        String searchBody = fullBody.replace('&nbsp;', ' ').replace('&lt;', '<').replace('&gt;', '>');

        // 3. Find the Split Point
        Matcher m = getHeaderPattern().matcher(searchBody);
        
        Integer splitIndex = -1;
        if (m.find()) {
            splitIndex = m.start();
        }

        // 4. Split and Return
        if (splitIndex != -1 && splitIndex > 0) {
            res.newContent = fullBody.substring(0, splitIndex);
            res.historyContent = fullBody.substring(splitIndex);
            res.hasHistory = true;
        } else {
            res.newContent = fullBody;
            res.historyContent = '';
            res.hasHistory = false;
        }

        return res;
    }

    // --- REGEX PATTERNS ---
    private static Pattern getHeaderPattern() {
        String p1 = 'On\\s+[A-Za-z]{3},?.+?wrote:';                         // "On Tue, 25 Nov... wrote:"
        String p2 = '-+\\s*Original Message\\s*-+';                          // "----- Original Message -----"
        String p3 = 'From:\\s+.*\\n?Sent:\\s+.*\\n?To:\\s+.*';               // Outlook "From: ... Sent: ... To:"
        String p4 = '<div class="gmail_quote">';                             // Gmail Quote Block
        String p5 = '________________________________';                      // Common underscore separator

        return Pattern.compile('(?is)(' + p1 + '|' + p2 + '|' + p3 + '|' + p4 + '|' + p5 + ')');
    }
}