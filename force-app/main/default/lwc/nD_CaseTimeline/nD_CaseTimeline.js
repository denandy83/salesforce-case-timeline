import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex'; 
import getTimelineData from '@salesforce/apex/ND_CaseTimelineController.getTimelineData';

export default class Nd_CaseTimeline extends LightningElement {
    @api recordId; 
    @track allItems = [];
    @track showEmail = true;
    @track showPublic = true;
    @track showInternal = true;
    @track showSystem = false;
    @track sortDirection = 'desc'; 
    wiredResult;

    @wire(getTimelineData, { caseId: '$recordId' })
    wiredData(result) {
        this.wiredResult = result;
        const { error, data } = result;
        if (data) {
            this.allItems = data.map(item => ({
                ...item,
                historyExpanded: false,
                
                // --- ADDED !important TO FORCE COLOR ---
                rowStyle: item.isInternal 
                    ? 'background-color: #fff7d6 !important; border: 1px solid #e6d38e;' 
                    : 'background-color: white;',
                
                boxClass: 'slds-box slds-box_x-small slds-m-bottom_small',
                isEmailCategory: item.category === 'Email',
                isPublicCategory: item.category === 'Public',
                isInternalCategory: item.category === 'Internal',
                isSystemCategory: item.category === 'System'
            }));
        } else if (error) {
            console.error('Error fetching timeline', error);
        }
    }
    
    // ... Same Getters/Handlers ...
    get sortIcon() { return this.sortDirection === 'desc' ? 'utility:arrowdown' : 'utility:arrowup'; }
    get sortLabel() { return this.sortDirection === 'desc' ? 'Newest First' : 'Oldest First'; }
    get filteredData() {
        let result = this.allItems.filter(item => {
            if (item.category === 'Email' && this.showEmail) return true;
            if (item.category === 'Public' && this.showPublic) return true;
            if (item.category === 'Internal' && this.showInternal) return true;
            if (item.category === 'System' && this.showSystem) return true;
            return false;
        });
        return [...result].sort((a, b) => {
            const dateA = new Date(a.createdDate);
            const dateB = new Date(b.createdDate);
            return this.sortDirection === 'desc' ? dateB - dateA : dateA - dateB;
        });
    }
    get hasData() { return this.filteredData && this.filteredData.length > 0; }
    handleToggle(event) {
        const name = event.target.name;
        const checked = event.target.checked;
        if (name === 'email') this.showEmail = checked;
        if (name === 'public') this.showPublic = checked;
        if (name === 'internal') this.showInternal = checked;
        if (name === 'system') this.showSystem = checked;
    }
    handleSortToggle() { this.sortDirection = this.sortDirection === 'desc' ? 'asc' : 'desc'; }
    handleRefresh() { refreshApex(this.wiredResult); }
    handleHistoryToggle(event) {
        event.preventDefault();
        const clickedId = event.currentTarget.dataset.id;
        this.allItems = this.allItems.map(item => {
            if (item.id === clickedId) { return { ...item, historyExpanded: !item.historyExpanded }; }
            return item;
        });
    }
}