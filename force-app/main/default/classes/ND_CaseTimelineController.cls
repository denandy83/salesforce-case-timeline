public without sharing class ND_CaseTimelineController {

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
        List<CaseFeed> feeds = [SELECT Id, Body, CreatedDate, CreatedBy.Name, Type, Visibility,
                                     (SELECT FieldName, OldValue, NewValue FROM FeedTrackedChanges) 
                                FROM CaseFeed 
                                WHERE ParentId = :caseId 
                                ORDER BY CreatedDate DESC];

        for(CaseFeed cf : feeds) {
            if (cf.Type == 'EmailMessageEvent') continue;

            TimelineItem item = new TimelineItem();
            item.id = cf.Id;
            item.createdDate = cf.CreatedDate;
            item.author = cf.CreatedBy.Name;
            item.hasHistory = false;

            // Categorization
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
            
            String rawBody = (cf.Body != null) ? cf.Body : '';
            String cleanBody = rawBody.unescapeHtml4().unescapeHtml4().replace('&nbsp;', ' ');
            String parsedResult = null;

            // PRIORITY 1: Check Main Body for JSON
            if (cleanBody.containsIgnoreCase('feedEvent') || cleanBody.contains('{"fu"')) {
                parsedResult = parseFeedEventString(cleanBody, statusMap);
            }

            if (parsedResult != null) {
                item.body = parsedResult;
            }
            // PRIORITY 2: Check Child Table
            else if (cf.FeedTrackedChanges != null && !cf.FeedTrackedChanges.isEmpty()) {
                List<String> changes = new List<String>();
                for (FeedTrackedChange ftc : cf.FeedTrackedChanges) {
                    
                    String field = (ftc.FieldName != null) ? ftc.FieldName : 'Field';
                    String oldV = String.valueOf(ftc.OldValue);
                    String newV = String.valueOf(ftc.NewValue);

                    // --- CRITICAL FIX: Check if the Old/New Value ITSELF is the JSON blob ---
                    String potentialJson = (oldV != null && oldV.contains('{"fu"')) ? oldV : 
                                           (newV != null && newV.contains('{"fu"')) ? newV : null;

                    if (potentialJson != null) {
                        String fix = parseFeedEventString(potentialJson, statusMap);
                        if (fix != null) {
                            changes.add(fix);
                            continue; // Found JSON in column, use the parsed version
                        }
                    }

                    // Standard Field Mapping
                    if (field == 'Status') {
                        if (statusMap.containsKey(oldV)) oldV = statusMap.get(oldV);
                        if (statusMap.containsKey(newV)) newV = statusMap.get(newV);
                    }
                    if (oldV == null) oldV = '(blank)';
                    if (newV == null) newV = '(blank)';
                    
                    if (oldV == '(blank)' && newV == '(blank)') {
                         changes.add('<b>' + field + '</b>: <i>(Updated)</i>');
                    } else {
                         changes.add('<b>' + field + '</b>: ' + oldV + ' &rarr; ' + newV);
                    }
                }
                item.body = String.join(changes, '<br/>');
            } 
            // PRIORITY 3: Fallback
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

    // --- HELPER: JSON PARSER ---
    private static String parseFeedEventString(String cleanBody, Map<String, String> statusMap) {
        try {
            Integer idxStart = cleanBody.indexOf('{');
            Integer idxEnd = cleanBody.lastIndexOf('}');
            
            if (idxStart == -1 || idxEnd == -1 || idxEnd <= idxStart) return null;

            String jsonPart = cleanBody.substring(idxStart, idxEnd + 1);
            jsonPart = jsonPart.replace('“', '"').replace('”', '"'); // Sanitize quotes

            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(jsonPart);
            
            if (root.containsKey('fu')) {
                List<Object> fieldUpdates = (List<Object>) root.get('fu');
                for (Object itemObj : fieldUpdates) {
                    Map<String, Object> updateMap = (Map<String, Object>) itemObj;
                    
                    String field = String.valueOf(updateMap.get('fn')); 
                    String oldV = String.valueOf(updateMap.get('ov')); 
                    String newV = String.valueOf(updateMap.get('nv')); 
                    
                    if (field == 'Status') {
                        if (statusMap.containsKey(oldV)) oldV = statusMap.get(oldV);
                        if (statusMap.containsKey(newV)) newV = statusMap.get(newV);
                        
                        if (String.isBlank(oldV) || oldV == 'null') oldV = '(blank)';
                        if (String.isBlank(newV) || newV == 'null') newV = '(blank)';
                        
                        return '<b>' + field + '</b>: ' + oldV + ' &rarr; ' + newV;
                    }
                }
            }
            return null;
        } catch (Exception e) {
            return null; 
        }
    }

    private static Map<String, String> getStatusMap() {
        Map<String, String> m = new Map<String, String>();
        // RESTORED FULL MAPPINGS
        m.put('1', 'New');
        m.put('2', 'On Hold');
        m.put('3', 'Closed');
        m.put('6', 'Open');
        m.put('7', 'Working');
        m.put('8', 'Waiting for Customer');
        m.put('9', 'Solved');
        
        try {
            Schema.DescribeFieldResult fieldResult = Case.Status.getDescribe();
            for(Schema.PicklistEntry f : fieldResult.getPicklistValues()) {
                m.put(f.getValue(), f.getLabel());
                m.put(f.getLabel(), f.getLabel());
            }
        } catch (Exception e) { }
        return m;
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