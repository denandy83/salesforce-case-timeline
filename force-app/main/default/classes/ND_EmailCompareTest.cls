@isTest
public class ND_EmailCompareTest {
    @isTest
    static void testAll() {
        ND_EmailCompare.FlowInput i = new ND_EmailCompare.FlowInput();
        i.currentText = 'New\nFrom: x\nSent: y';
        i.characterLimit = 5;
        ND_EmailCompare.parseForFlow(new List<ND_EmailCompare.FlowInput>{i});
        
        ND_EmailCompare.parsePlainText('test', 0);
        ND_EmailCompare.parsePlainText('test\nOn x wrote:', 500);
        ND_EmailCompare.parsePlainText('test\n-----Original Message-----', 500);
        ND_EmailCompare.parsePlainText('test\n________________________________', 500);
        ND_EmailCompare.parsePlainText('test\nDa: x\nInviato: y', 500);
        ND_EmailCompare.parsePlainText(null, null);
    }
}