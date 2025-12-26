public with sharing class ND_EmailCompare {

    // ==========================================
    // 1. FLOW INPUT WRAPPER
    // ==========================================
    public class FlowInput {
        @InvocableVariable(label='Current Text Body' required=true)
        public String currentText;

        @InvocableVariable(label='Character Limit (Optional)' required=false)
        public Integer characterLimit;
    }

    // ==========================================
    // 2. OUTPUT RESULT
    // ==========================================
    public class ComparisonResult {
        @InvocableVariable @AuraEnabled public String newContentPlain;
    }

    // ==========================================
    // 3. INVOCABLE METHOD
    // ==========================================
    @InvocableMethod(label='ND_Email Compare (Text Only)' description='Splits plain text at history separator. Respects optional char limit if provided.' category='Email')
    public static List<ComparisonResult> parseForFlow(List<FlowInput> inputs) {
        List<ComparisonResult> results = new List<ComparisonResult>();
        
        for (FlowInput input : inputs) {
            results.add(parsePlainText(input.currentText, input.characterLimit));
        }
        return results;
    }

    // ==========================================
    // 4. MAIN LOGIC
    // ==========================================
    public static ComparisonResult parsePlainText(String textBody, Integer charLimit) {
        ComparisonResult res = new ComparisonResult();
        
        // 1. Handle Empty Input
        if (String.isBlank(textBody)) {
            res.newContentPlain = '';
            return res;
        }

        String processedText = textBody;
        Integer splitIndex = textBody.length(); // Default to end of string (full text)

        // 2. REGEX SPLIT: Find "From:", "Original Message", etc.
        try {
            // Limit search to first 10k chars to prevent regex timeout on massive text blobs
            String textToSearch = (processedText.length() > 10000) ? processedText.substring(0, 10000) : processedText;
            
            Matcher m = getHeaderPattern().matcher(textToSearch);
            if (m.find()) {
                // If found, this is our potential cut point
                splitIndex = m.start();
            }
        } catch (Exception e) {
            System.debug('ND_EmailCompare: Regex match failed: ' + e.getMessage());
        }

        // 3. APPLY LOGIC: "Whichever happens first"
        // If a valid character limit is defined, compare it with the splitIndex
        if (charLimit != null && charLimit > 0) {
            if (charLimit < splitIndex) {
                splitIndex = charLimit;
            }
        }
        
        // 4. TRUNCATE
        // Only substring if the calculated splitIndex is actually smaller than the text length
        if (splitIndex < processedText.length()) {
            res.newContentPlain = processedText.substring(0, splitIndex);
        } else {
            res.newContentPlain = processedText;
        }

        return res;
    }

    // ==========================================
    // 5. REGEX PATTERNS (JS Parity)
    // ==========================================
    private static Pattern getHeaderPattern() {
        // Matches "On ... wrote:", "Original Message", "From: ... Sent:", etc.
        String p1 = 'On\\s+[A-Za-z]{3}.{0,200}?wrote:'; 
        String p2 = '-{3,}\\s*(?:Original|Forwarded)\\s+Message\\s*-{3,}';
        String p3 = '(?:From:|<b>From:</b>).{1,300}?(?:Sent:|<b>Sent:</b>)';
        String p4 = 'From:.{1,100}?(&lt;|<).+?@.+?(&gt;|>)';
        String p5 = 'De\\s*:.{1,100}?Envoy.{1,100}?:';
        String p6 = '_{20,}';

        return Pattern.compile('(?is)(' + p1 + '|' + p2 + '|' + p3 + '|' + p4 + '|' + p5 + '|' + p6 + ')');
    }
}