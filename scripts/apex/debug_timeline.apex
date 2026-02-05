String caseId = '500TX00000VDzoeYAD';

// 1. Get Emails
List<EmailMessage> emails = [SELECT Id, MessageDate, Subject FROM EmailMessage WHERE ParentId = :caseId];

// 2. Get FeedItems
List<FeedItem> feeds = [SELECT Id, CreatedDate, Body, Type, Visibility FROM FeedItem WHERE ParentId = :caseId];

class ItemWrapper implements Comparable {
    public String id;
    public DateTime dt;
    public String type;
    
    public ItemWrapper(String i, DateTime d, String t) {
        id = i; dt = d; type = t;
    }
    
    public Integer compareTo(Object other) {
        ItemWrapper o = (ItemWrapper)other;
        if (dt < o.dt) return 1; // DESC
        if (dt > o.dt) return -1;
        return 0;
    }
}

List<ItemWrapper> all = new List<ItemWrapper>();
for(EmailMessage e : emails) all.add(new ItemWrapper(e.Id, e.MessageDate, 'Email'));
for(FeedItem f : feeds) all.add(new ItemWrapper(f.Id, f.CreatedDate, 'FeedItem (' + f.Visibility + ')'));

all.sort();

Integer i = 1;
for(ItemWrapper w : all) {
    System.debug('Item ' + i + ': ' + w.dt + ' | ' + w.dt.getTime() + ' | ' + w.type + ' | ' + w.id);
    i++;
}