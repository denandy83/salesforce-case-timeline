public with sharing class ND_EmailCompare {

    // ==========================================
    // 1. FLOW INPUT WRAPPER
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
    // 2. OUTPUT RESULT
    // ==========================================
    public class ComparisonResult {
        @InvocableVariable @AuraEnabled public String newContent;      
        @InvocableVariable @AuraEnabled public String newContentPlain;  
        @InvocableVariable @AuraEnabled public String historyContent;   
        @InvocableVariable @AuraEnabled public Boolean hasHistory;      
    }

    // ==========================================
    // 3. INVOCABLE METHOD
    // ==========================================
    @InvocableMethod(label='ND_Email Compare' description='Splits email body into New Content and History' category='Email')
    public static List<ComparisonResult> parseForFlow(List<FlowInput> inputs) {
        List<ComparisonResult> results = new List<ComparisonResult>();
        
        for (FlowInput input : inputs) {
            results.add(parse(input.currentHtml, input.currentText, input.previousHtml, input.previousText));
        }
        return results;
    }

    // ==========================================
    // 4. MAIN LOGIC
    // ==========================================
    public static ComparisonResult parse(String currentHtml, String currentText, String previousHtml, String previousText) {
        ComparisonResult res = new ComparisonResult();
        
        try {
            // 1. Get the HTML Body
            String fullBody = '';
            if (String.isNotBlank(currentHtml)) {
                fullBody = currentHtml;
            } else if (String.isNotBlank(currentText)) {
                fullBody = currentText.replace('\n', '<br/>');
            }

            // 1a. Store plain text for parallel processing
            String plainTextBody = String.isNotBlank(currentText) ? currentText : '';

            // Handle null/empty bodies safely
            if (String.isBlank(fullBody)) {
                res.newContent = '';
                res.newContentPlain = '';
                res.historyContent = '';
                res.hasHistory = false;
                return res;
            }

            System.debug('ND_EmailCompare: Starting parse, fullBody length: ' + fullBody.length());
            System.debug('ND_EmailCompare: plainTextBody length: ' + plainTextBody.length());

            // 2. CLEAN INVISIBLE CLUTTER FIRST (before any processing)
            String cleanedBody = '';
            try {
                cleanedBody = removeInvisibleClutter(fullBody);
                System.debug('ND_EmailCompare: After removeInvisibleClutter, length: ' + cleanedBody.length());
            } catch (Exception e) {
                System.debug('ND_EmailCompare: removeInvisibleClutter failed: ' + e.getMessage());
                // Fallback: use original body
                cleanedBody = fullBody;
            }

            // 3. Find the Split Point (email history separator)
            String searchBody = cleanedBody.replace('&nbsp;', ' ').replace('&lt;', '<').replace('&gt;', '>');
            
            // Safety: Limit search to prevent regex timeout on huge emails
            Integer MAX_SEARCH_LIMIT = 10000;
            String bodyToSearch = searchBody;
            if (searchBody.length() > MAX_SEARCH_LIMIT) {
                bodyToSearch = searchBody.substring(0, MAX_SEARCH_LIMIT);
            }
            
            Integer splitIndex = -1;
            try {
                // Find the FIRST occurrence of email history separator
                Matcher m = getHeaderPattern().matcher(bodyToSearch);
                if (m.find()) {
                    splitIndex = m.start();
                    
                    // IMPORTANT: Adjust splitIndex to avoid cutting through HTML tags
                    // Move backwards to find the start of the tag that contains this match
                    splitIndex = adjustSplitPointToTagBoundary(cleanedBody, splitIndex);
                }
                System.debug('ND_EmailCompare: Split index found at: ' + splitIndex);
            } catch (Exception e) {
                System.debug('ND_EmailCompare: Regex pattern matching failed: ' + e.getMessage());
                splitIndex = -1;
            }

            // 4. Split at history separator (if found)
            if (splitIndex != -1 && splitIndex > 0) {
                res.newContent = cleanedBody.substring(0, splitIndex);
                res.historyContent = cleanedBody.substring(splitIndex);
                res.hasHistory = true;
            } else if (splitIndex == 0) {
                // Email starts immediately with history separator (forwarded message)
                res.newContent = '[No data - Forwarded message]';
                res.historyContent = cleanedBody;
                res.hasHistory = true;
            } else {
                res.newContent = cleanedBody;
                res.historyContent = '';
                res.hasHistory = false;
            }

            // 4a. Apply same split logic to plain text
            Integer plainSplitIndex = -1;
            if (String.isNotBlank(plainTextBody)) {
                try {
                    String plainBodyToSearch = plainTextBody;
                    if (plainTextBody.length() > MAX_SEARCH_LIMIT) {
                        plainBodyToSearch = plainTextBody.substring(0, MAX_SEARCH_LIMIT);
                    }
                    
                    Matcher plainMatcher = getHeaderPattern().matcher(plainBodyToSearch);
                    if (plainMatcher.find()) {
                        plainSplitIndex = plainMatcher.start();
                    }
                    System.debug('ND_EmailCompare: Plain text split index found at: ' + plainSplitIndex);
                } catch (Exception e) {
                    System.debug('ND_EmailCompare: Plain text pattern matching failed: ' + e.getMessage());
                    plainSplitIndex = -1;
                }
                
                // Split plain text at history separator
                if (plainSplitIndex != -1 && plainSplitIndex > 0) {
                    res.newContentPlain = plainTextBody.substring(0, plainSplitIndex);
                } else if (plainSplitIndex == 0) {
                    // Plain text starts immediately with history separator (forwarded message)
                    res.newContentPlain = '[No data - Forwarded message]';
                } else {
                    res.newContentPlain = plainTextBody;
                }
            } else {
                res.newContentPlain = '';
            }

            System.debug('ND_EmailCompare: Before char limit - newContent length: ' + (res.newContent != null ? res.newContent.length() : 0));

            // 5. Apply 1950 CHARACTER LIMIT based on VISIBLE TEXT
            try {
                res = applyVisibleCharacterLimit(res, 1950);
                System.debug('ND_EmailCompare: After char limit - newContent length: ' + (res.newContent != null ? res.newContent.length() : 0));
            } catch (Exception e) {
                System.debug('ND_EmailCompare: applyVisibleCharacterLimit failed: ' + e.getMessage());
                // Continue without character limit if it fails
            }

            // 6. Apply 1950 character limit to plain text (simpler - just count chars)
            if (String.isNotBlank(res.newContentPlain) && res.newContentPlain.length() > 1950) {
                res.newContentPlain = res.newContentPlain.substring(0, 1950);
            }
            System.debug('ND_EmailCompare: newContentPlain length: ' + (res.newContentPlain != null ? res.newContentPlain.length() : 0));

            return res;
            
        } catch (Exception e) {
            // FALLBACK: If anything fails, return simple result
            System.debug('ND_EmailCompare: CRITICAL ERROR in parse: ' + e.getMessage());
            System.debug('ND_EmailCompare: Stack trace: ' + e.getStackTraceString());
            
            // Return simple result without processing
            res.newContent = (String.isNotBlank(currentHtml) ? currentHtml : 
                             (String.isNotBlank(currentText) ? currentText.replace('\n', '<br/>') : ''));
            res.newContentPlain = (String.isNotBlank(currentText) ? currentText : '');
            res.historyContent = '';
            res.hasHistory = false;
            return res;
        }
    }

    // ==========================================
    // HELPER: Remove Invisible HTML Clutter
    // ==========================================
    private static String removeInvisibleClutter(String html) {
        if (String.isBlank(html)) return html;
        
        // Remove <head> sections entirely (with all contents)
        html = html.replaceAll('(?is)<head[^>]*>.*?</head>', '');
        
        // Remove <style> tags (sometimes outside head)
        html = html.replaceAll('(?is)<style[^>]*>.*?</style>', '');
        
        // Remove <script> tags
        html = html.replaceAll('(?is)<script[^>]*>.*?</script>', '');
        
        // Remove HTML comments
        html = html.replaceAll('(?is)<!--.*?-->', '');
        
        // Remove XML declarations
        html = html.replaceAll('(?is)<\\?xml[^>]*\\?>', '');
        
        // Remove MS Office specific tags that don't render
        html = html.replaceAll('(?is)<o:[^>]*>', '');
        html = html.replaceAll('(?is)</o:[^>]*>', '');
        html = html.replaceAll('(?is)<v:[^>]*>', '');
        html = html.replaceAll('(?is)</v:[^>]*>', '');
        html = html.replaceAll('(?is)<w:[^>]*>', '');
        html = html.replaceAll('(?is)</w:[^>]*>', '');
        
        return html;
    }

    // ==========================================
    // HELPER: Apply Character Limit Based on Visible Text
    // ==========================================
    private static ComparisonResult applyVisibleCharacterLimit(ComparisonResult res, Integer charLimit) {
        if (res.newContent == null || res.newContent.length() == 0) {
            return res;
        }
        
        // Calculate visible character count (strip all HTML tags)
        String visibleText = res.newContent.replaceAll('(?i)<[^>]+>', '').replaceAll('&nbsp;', ' ').replaceAll('&[a-z]+;', ' ');
        
        // If visible text is under limit, return as-is
        if (visibleText.length() <= charLimit) {
            return res;
        }
        
        // Need to truncate - find where to cut in the HTML to get ~charLimit visible chars
        Integer cutPoint = findHtmlCutPoint(res.newContent, charLimit);
        
        if (cutPoint > 0 && cutPoint < res.newContent.length()) {
            // Split the content
            String truncatedContent = res.newContent.substring(0, cutPoint);
            String overflow = res.newContent.substring(cutPoint);
            
            // Append overflow to history
            if (String.isNotBlank(res.historyContent)) {
                res.historyContent = overflow + '<hr>' + res.historyContent;
            } else {
                res.historyContent = overflow;
            }
            
            res.newContent = truncatedContent;
            res.hasHistory = true; // Enable "Show More" button
        }
        
        return res;
    }

    // ==========================================
    // HELPER: Find Cut Point in HTML for Character Limit
    // ==========================================
    private static Integer findHtmlCutPoint(String html, Integer visibleCharLimit) {
        Integer visibleCount = 0;
        Integer htmlPosition = 0;
        Boolean insideTag = false;
        Boolean insideEntity = false;
        
        while (htmlPosition < html.length() && visibleCount < visibleCharLimit) {
            String currentChar = html.substring(htmlPosition, htmlPosition + 1);
            
            // Track if we're inside an HTML tag
            if (currentChar == '<') {
                insideTag = true;
            } else if (currentChar == '>') {
                insideTag = false;
                htmlPosition++;
                continue;
            }
            
            // Track if we're inside an HTML entity (&nbsp; &lt; etc)
            if (currentChar == '&') {
                insideEntity = true;
            } else if (insideEntity && currentChar == ';') {
                insideEntity = false;
                visibleCount++; // Count entity as 1 visible char
                htmlPosition++;
                continue;
            }
            
            // Count visible characters (not inside tags or entities)
            if (!insideTag && !insideEntity) {
                visibleCount++;
            }
            
            htmlPosition++;
        }
        
        // Try to find a good breaking point (end of tag, end of sentence, etc.)
        Integer goodBreakPoint = findGoodBreakPoint(html, htmlPosition);
        
        return goodBreakPoint;
    }

    // ==========================================
    // HELPER: Find Good Breaking Point (tag boundary, sentence end)
    // ==========================================
    private static Integer findGoodBreakPoint(String html, Integer position) {
        // Look ahead up to 200 chars for a good break point
        Integer searchEnd = Math.min(position + 200, html.length());
        
        // Priority 1: End of closing tag (</p>, </div>, </span>)
        Integer closingTag = html.indexOf('</', position);
        if (closingTag != -1 && closingTag < searchEnd) {
            Integer tagEnd = html.indexOf('>', closingTag);
            if (tagEnd != -1 && tagEnd < searchEnd) {
                return tagEnd + 1;
            }
        }
        
        // Priority 2: End of sentence (. ! ?)
        for (Integer i = position; i < searchEnd; i++) {
            String c = html.substring(i, i + 1);
            if (c == '.' || c == '!' || c == '?') {
                // Make sure it's followed by space or tag
                if (i + 1 < html.length()) {
                    String next = html.substring(i + 1, i + 2);
                    if (next == ' ' || next == '<' || next == '\n') {
                        return i + 1;
                    }
                }
            }
        }
        
        // Priority 3: End of any tag
        Integer anyTag = html.indexOf('>', position);
        if (anyTag != -1 && anyTag < searchEnd) {
            return anyTag + 1;
        }
        
        // Fallback: use original position
        return position;
    }

    // ==========================================
    // HELPER: Adjust Split Point to Tag Boundary
    // ==========================================
    private static Integer adjustSplitPointToTagBoundary(String html, Integer splitIndex) {
        if (splitIndex <= 0 || splitIndex >= html.length()) {
            return splitIndex;
        }
        
        // Look backwards from splitIndex to find the last complete tag boundary
        // We want to find the closing tag (</div>, </p>, </span>) before our split point
        
        Integer adjustedIndex = splitIndex;
        
        // Search backwards up to 500 chars to find a closing tag
        Integer searchStart = Math.max(0, splitIndex - 500);
        
        // Find the last occurrence of a closing tag before splitIndex
        for (Integer i = splitIndex - 1; i >= searchStart; i--) {
            if (i + 1 < html.length() && html.substring(i, i + 1) == '>') {
                // Found a closing bracket, check if it's a closing tag
                // Look backwards to find the opening bracket
                Integer tagStart = html.lastIndexOf('<', i);
                if (tagStart >= 0) {
                    String tag = html.substring(tagStart, i + 1);
                    // Check if it's a closing tag (</...>) or self-closing (<.../>) or <br>
                    if (tag.startsWith('</') || tag.endsWith('/>') || tag.toLowerCase().contains('<br')) {
                        // This is a good boundary - split right after this tag
                        adjustedIndex = i + 1;
                        break;
                    }
                }
            }
        }
        
        return adjustedIndex;
    }

    // ==========================================
    // REGEX PATTERNS (Simplified to avoid timeout)
    // ==========================================
    private static Pattern getHeaderPattern() {
        // Simplified patterns - removed complex lookarounds that cause timeout

        // 1. Standard: "On ... wrote:"
        String p1 = 'On\\s+[A-Za-z]{3}.{1,200}?wrote:'; 

        // 2. Original Message Separator
        String p2 = '-{3,}\\s*Original Message\\s*-{3,}';

        // 3. Email Header (English): "From: Name <email@address>"
        String p3 = 'From:.{1,100}?<.+?@.+?>';

        // 4. Email Header (French): "De : ... Envoyé : ... À :"
        String p4 = 'De\\s*:.{1,100}?Envoy.{1,100}?:\\s*.{1,100}?:';

        // 5. Forwarded Message
        String p5 = '-{3,}\\s*Forwarded [Mm]essage\\s*-{3,}';

        // 6. Gmail Quote Block
        String p6 = '<div class="gmail_quote">';

        // 7. Underscore Separator (at least 20 underscores)
        String p7 = '_{20,}';

        // 8. Standalone Email Address (email in angle brackets on its own)
        // Matches: <someone@example.com> when it appears standalone
        String p8 = '<[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}>';

        return Pattern.compile('(?is)(' + p1 + '|' + p2 + '|' + p3 + '|' + p4 + '|' + p5 + '|' + p6 + '|' + p7 + '|' + p8 + ')');
    }
}