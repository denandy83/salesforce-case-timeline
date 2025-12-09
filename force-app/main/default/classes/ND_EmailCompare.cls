public with sharing class ND_EmailCompare {

    public class ComparisonResult {
        public String newContent;      // The fresh reply
        public String historyContent;  // The hidden history part
        public Boolean hasHistory;     // Should we show the button?
    }

    public static ComparisonResult parse(String currentHtml, String currentText, String previousHtml, String previousText) {
        ComparisonResult res = new ComparisonResult();
        
        // 1. Get the HTML Body (or convert Text to HTML if needed)
        String fullBody = '';
        if (String.isNotBlank(currentHtml)) {
            fullBody = currentHtml;
        } else if (String.isNotBlank(currentText)) {
            fullBody = currentText.replace('\n', '<br/>');
        }

        // 2. Prepare for Matching (Fix &nbsp; and HTML entities that break Regex)
        // We create a temporary string just for searching, to keep indices aligned.
        String searchBody = fullBody.replace('&nbsp;', ' ').replace('&lt;', '<').replace('&gt;', '>');

        // 3. Find the Split Point using Regex (The safest method)
        // We look for the standard separators.
        Matcher m = getHeaderPattern().matcher(searchBody);
        
        Integer splitIndex = -1;
        if (m.find()) {
            splitIndex = m.start();
        }

        // 4. Split and Return
        if (splitIndex != -1 && splitIndex > 0) {
            // Success! The 'New' content is everything before the match.
            res.newContent = fullBody.substring(0, splitIndex);
            
            // The 'History' content is the match (The header) + everything after.
            // This hides the "On Tue..." or "Original Message" line inside the toggle.
            res.historyContent = fullBody.substring(splitIndex);
            res.hasHistory = true;
        } else {
            // Fallback: If no separator found, show everything as new.
            res.newContent = fullBody;
            res.historyContent = '';
            res.hasHistory = false;
        }

        return res;
    }

    // --- REGEX PATTERNS ---
    private static Pattern getHeaderPattern() {
        // We combine multiple common patterns into one regex using OR (|)
        // (?i) = Case Insensitive
        // (?s) = Dot matches newlines (crucial for Outlook headers)
        
        String p1 = 'On\\s+[A-Za-z]{3},?.+?wrote:';                         // "On Tue, 25 Nov... wrote:"
        String p2 = '-+\\s*Original Message\\s*-+';                          // "----- Original Message -----"
        String p3 = 'From:\\s+.*\\n?Sent:\\s+.*\\n?To:\\s+.*';               // Outlook "From: ... Sent: ... To:"
        String p4 = '<div class="gmail_quote">';                             // Gmail Quote Block
        String p5 = '________________________________';                      // Common underscore separator

        return Pattern.compile('(?is)(' + p1 + '|' + p2 + '|' + p3 + '|' + p4 + '|' + p5 + ')');
    }
}