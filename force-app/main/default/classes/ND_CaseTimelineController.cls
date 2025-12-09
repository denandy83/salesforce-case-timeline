public with sharing class ND_CaseTimelineController {
    
    public class TimelineItem implements Comparable {
        @AuraEnabled public String id;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public String title;
        @AuraEnabled public String body;        
        @AuraEnabled public String historyBody; 
        @AuraEnabled public Boolean hasHistory;
        @AuraEnabled public String author;
        @AuraEnabled public String category;    
        @AuraEnabled public Boolean isInternal; 
        @AuraEnabled public Boolean historyExpanded = false; 

        public Integer compareTo(Object compareTo) {
            TimelineItem other = (TimelineItem) compareTo;
            if (this.createdDate < other.createdDate) return 1;
            if (this.createdDate > other.createdDate) return -1;
            return 0;
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<TimelineItem> getTimelineData(Id caseId) {
        List<TimelineItem> combinedList = new List<TimelineItem>();
        Map<String, String> statusMap = getStatusMap();

        // 1. Fetch Emails
        for(EmailMessage em : [SELECT Id, Subject, HtmlBody, TextBody, MessageDate, FromName 
                               FROM EmailMessage 
                               WHERE ParentId = :caseId 
                               ORDER BY MessageDate DESC]) {
            TimelineItem item = new TimelineItem();
            item.id = em.Id;
            item.createdDate = em.MessageDate;
            item.category = 'Email'; 
            item.isInternal = false; 
            item.title = (em.Subject != null) ? '✉️ ' + em.Subject : 'No Subject';
            item.author = em.FromName;

            ND_EmailCompare.ComparisonResult res = ND_EmailCompare.parse(
                em.HtmlBody, em.TextBody, null, null
            );

            item.body = cleanHtml(res.newContent);
            item.historyBody = cleanHtml(res.historyContent);
            item.hasHistory = res.hasHistory;
            combinedList.add(item);
        }

        // 2. Fetch Chatter
        for(CaseFeed cf : [SELECT Id, Body, CreatedDate, CreatedBy.Name, Type, Visibility,
                                  (SELECT FieldName, OldValue, NewValue FROM FeedTrackedChanges) 
                           FROM CaseFeed 
                           WHERE ParentId = :caseId 
                           ORDER BY CreatedDate DESC]) {
            
            if (cf.Type == 'EmailMessageEvent') continue;

            TimelineItem item = new TimelineItem();
            item.id = cf.Id;
            item.createdDate = cf.CreatedDate;
            item.author = cf.CreatedBy.Name;
            item.hasHistory = false;

            // CATEGORIZATION
            Boolean isSystemType = (cf.Type == 'TrackedChange' || 
                                    cf.Type == 'CreateRecordEvent' || 
                                    cf.Type == 'ActivityEvent' ||
                                    cf.Type == 'CaseCommentPost' ||
                                    cf.Type == 'ChangeStatusPost' || 
                                    cf.CreatedBy.Name == 'Automated Process');

            if (isSystemType) {
                item.category = 'System';
                item.isInternal = true; 
                item.title = '⚙️ ' + formatSystemTitle(cf.Type);
            } else if (cf.Visibility == 'AllUsers') {
                item.category = 'Public';
                item.isInternal = false; 
                item.title = '💬 Public Post';
            } else {
                item.category = 'Internal';
                item.isInternal = true; 
                item.title = '🔒 Internal Note';
            }
            
            // BODY PROCESSING
            String rawBody = (cf.Body != null) ? cf.Body : '';
            // Double Unescape to be safe against &amp;quot;
            String cleanBody = rawBody.unescapeHtml4().unescapeHtml4(); 

            // A. Check Child Table (Cleanest data)
            if (cf.FeedTrackedChanges != null && !cf.FeedTrackedChanges.isEmpty()) {
                List<String> changes = new List<String>();
                for (FeedTrackedChange ftc : cf.FeedTrackedChanges) {
                    String field = (ftc.FieldName != null) ? ftc.FieldName : 'Field';
                    String oldV = String.valueOf(ftc.OldValue);
                    String newV = String.valueOf(ftc.NewValue);

                    if (field == 'Status') {
                        if (statusMap.containsKey(oldV)) oldV = statusMap.get(oldV);
                        if (statusMap.containsKey(newV)) newV = statusMap.get(newV);
                    }
                    if (oldV == null) oldV = '(blank)';
                    if (newV == null) newV = '(blank)';
                    
                    if (oldV == '(blank)' && newV == '(blank)' && ftc.OldValue == null && ftc.NewValue == null) {
                         changes.add('<b>' + field + '</b>: <i>(Updated)</i>');
                    } else {
                         changes.add('<b>' + field + '</b>: ' + oldV + ' &rarr; ' + newV);
                    }
                }
                item.body = String.join(changes, '<br/>');
            } 
            // B. Jumbled JSON Detection (Regex Force)
            else if (cleanBody.contains('feedEvent:') || cleanBody.contains('{"fu":')) {
                // Use Regex Parser
                item.body = parseStatusJsonRegex(cleanBody, statusMap);
            }
            // C. Standard Body
            else if (String.isNotBlank(cleanBody)) {
                item.body = cleanBody;
            } else {
                item.body = '<i>[' + cf.Type + ']</i>';
            }

            combinedList.add(item);
        }

        combinedList.sort();
        return combinedList;
    }

    // --- REGEX PARSER: Extracts {"fu": ... } regardless of garbage text ---
    private static String parseStatusJsonRegex(String cleanBody, Map<String, String> statusMap) {
        try {
            // Pattern matches: { ... "fu": ... } 
            // We use non-greedy matching .*? to find the JSON block
            Pattern p = Pattern.compile('\\{.*?\"fu\":.*?\\}');
            Matcher m = p.matcher(cleanBody);
            
            if (m.find()) {
                String cleanJson = m.group(0); 
                
                Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(cleanJson);
                
                if (root.containsKey('fu')) {
                    List<Object> fieldUpdates = (List<Object>) root.get('fu');
                    if (!fieldUpdates.isEmpty()) {
                        Map<String, Object> updateMap = (Map<String, Object>) fieldUpdates[0];
                        String field = (String) updateMap.get('fn'); 
                        String oldV = (String) updateMap.get('ov'); 
                        String newV = (String) updateMap.get('nv'); 
                        
                        // Map 7 -> Working
                        if (field == 'Status') {
                            if (statusMap.containsKey(oldV)) oldV = statusMap.get(oldV);
                            if (statusMap.containsKey(newV)) newV = statusMap.get(newV);
                        }
                        
                        if (oldV == null) oldV = '(blank)';
                        if (newV == null) newV = '(blank)';
                        
                        return '<b>' + field + '</b>: ' + oldV + ' &rarr; ' + newV;
                    }
                }
            }
            // If Regex fails, debug it and return raw
            System.debug('JSON REGEX FAILED on: ' + cleanBody);
            return '<i>' + cleanBody + '</i>';
        } catch (Exception e) {
            System.debug('JSON PARSE EXCEPTION: ' + e.getMessage());
            return '<i>[Status Update - Details unavailable]</i>';
        }
    }

    private static Map<String, String> getStatusMap() {
        Map<String, String> resultMap = new Map<String, String>();
        for (CaseStatus cs : [SELECT MasterLabel, ApiName FROM CaseStatus]) {
            resultMap.put(cs.ApiName, cs.MasterLabel); 
            resultMap.put(cs.MasterLabel, cs.MasterLabel);
        }
        return resultMap;
    }

    private static String formatSystemTitle(String type) {
        if (type == 'TrackedChange') return 'Field Update';
        if (type == 'ChangeStatusPost') return 'Status Changed';
        if (type == 'CreateRecordEvent') return 'Record Created';
        return type;
    }

    private static String cleanHtml(String html) {
        if (String.isBlank(html)) return '';
        return html.replace('<html', '<div').replace('</html>', '</div>')
                   .replace('<body', '<div').replace('</body>', '</div>')
                   .replace('<!DOCTYPE html>', '');
    }
}