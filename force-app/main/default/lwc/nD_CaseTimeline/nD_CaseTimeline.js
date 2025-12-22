import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTimelineData from '@salesforce/apex/ND_CaseTimelineController.getTimelineData';
import checkForNewItems from '@salesforce/apex/ND_CaseTimelineController.checkForNewItems';

const POLLING_INTERVAL = 15000; // 15 seconds

export default class Nd_CaseTimeline extends NavigationMixin(LightningElement) {
    @track allItems = [];
    @track showEmail = true;
    @track showPublic = true;
    @track showInternal = true;
    @track showSystem = false;
    @track sortDirection = 'desc';
    @track isLoading = false;
    @track error;
    
    // Polling Variables
    @track isNewDataAvailable = false;
    lastRefreshDate; 
    _pollingTimer;

    _recordId;

    @api 
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.loadTimelineData();
        }
    }

    connectedCallback() {
        if (this.recordId) {
            this.loadTimelineData();
        }
    }

    disconnectedCallback() {
        this.stopPolling();
    }

    // --- POLLING LOGIC ---

    startPolling() {
        this.stopPolling(); // Clear existing timer
        
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pollingTimer = setInterval(() => {
            this.checkServerForUpdates();
        }, POLLING_INTERVAL);
    }

    stopPolling() {
        if (this._pollingTimer) {
            clearInterval(this._pollingTimer);
            this._pollingTimer = null;
        }
    }

    checkServerForUpdates() {
        // Don't poll if we lack context
        if (!this.recordId || !this.lastRefreshDate) return;

        checkForNewItems({ 
            caseId: this.recordId, 
            lastCheckDate: this.lastRefreshDate 
        })
        .then(hasNewData => {
            if (hasNewData) {
                this.isNewDataAvailable = true;
                this.stopPolling(); // Requirement: Stop polling once new data is found
            }
        })
        .catch(error => {
            console.error('Error polling:', error);
        });
    }

    // --- DATA LOADING ---

    loadTimelineData() {
        if (!this.recordId) return;
        
        this.stopPolling(); // Pause polling during load
        this.isLoading = true;
        this.error = undefined;
        this.isNewDataAvailable = false; // Hide banner
        
        // 1. Save timestamp BEFORE the query starts. 
        // Any item created after this moment will be caught by the next poll.
        this.lastRefreshDate = new Date().toISOString();

        getTimelineData({ caseId: this.recordId })
            .then(data => {
                this.allItems = data.map(item => ({
                    ...item,
                    historyExpanded: false,
                    rowStyle: '',
                    boxClass: item.isInternal 
                        ? 'slds-box slds-box_x-small slds-m-bottom_small internal-note'
                        : 'slds-box slds-box_x-small slds-m-bottom_small',
                    emailBadgeClass: item.isOutgoing 
                        ? 'slds-badge outgoing-email-badge'
                        : 'slds-badge slds-theme_success',
                    isEmailCategory: item.category === 'Email',
                    isPublicCategory: item.category === 'Public',
                    isInternalCategory: item.category === 'Internal',
                    isSystemCategory: item.category === 'System'
                }));
                
                this.isLoading = false;
                
                // Wait for render, then start polling
                setTimeout(() => {
                    this.renderedCallback();
                    this.startPolling(); 
                }, 0);
            })
            .catch(error => {
                this.error = error;
                this.isLoading = false;
            });
    }

    // --- (No changes needed below this line, keep existing helper methods) ---

    renderedCallback() {
        if (this.allItems && this.allItems.length > 0) {
            this.allItems.forEach(item => {
                const bodyContainer = this.template.querySelector(`[data-body-id="${item.id}"]`);
                if (bodyContainer && item.body && !bodyContainer.innerHTML) {
                    bodyContainer.innerHTML = item.body;
                    this.attachEventListeners(bodyContainer);
                }
                if (item.historyExpanded && item.historyBody) {
                    const historyContainer = this.template.querySelector(`[data-history-id="${item.id}"]`);
                    if (historyContainer && !historyContainer.innerHTML) {
                        historyContainer.innerHTML = item.historyBody;
                        this.attachEventListeners(historyContainer);
                    }
                }
            });
        }
    }

    attachEventListeners(container) {
        container.querySelectorAll('.copy-btn').forEach(btn => btn.addEventListener('click', this.handleCopyCode.bind(this)));
        container.querySelectorAll('.image-preview-link').forEach(link => link.addEventListener('click', this.handleImagePreviewClick.bind(this)));
        container.querySelectorAll('.mention-link').forEach(link => link.addEventListener('click', this.handleMentionClick.bind(this)));
    }

    handleCopyCode(event) {
        const btn = event.target;
        const code = btn.getAttribute('data-code');
        const cleanCode = code ? code.replace(/\\n/g, '\n') : '';
        navigator.clipboard.writeText(cleanCode).then(() => {
            btn.textContent = 'Copied!';
            setTimeout(() => { btn.textContent = 'Copy'; }, 2000);
        });
    }

    handleImagePreviewClick(event) {
        event.preventDefault(); event.stopPropagation();
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: { selectedRecordId: event.currentTarget.dataset.docId }
        });
    }

    handleMentionClick(event) {
        event.preventDefault(); event.stopPropagation();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.recordId, actionName: 'view' }
        });
    }

    get sortIcon() { return this.sortDirection === 'desc' ? 'utility:arrowdown' : 'utility:arrowup'; }
    get sortLabel() { return this.sortDirection === 'desc' ? 'Newest First' : 'Oldest First'; }
    get hasData() { return this.filteredData && this.filteredData.length > 0; }

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

    handleToggle(event) {
        const name = event.target.name;
        const checked = event.target.checked;
        if (name === 'email') this.showEmail = checked;
        if (name === 'public') this.showPublic = checked;
        if (name === 'internal') this.showInternal = checked;
        if (name === 'system') this.showSystem = checked;
    }

    handleSortToggle() { this.sortDirection = this.sortDirection === 'desc' ? 'asc' : 'desc'; }

    handleCollapseAll() {
        this.allItems = [...this.allItems.map(item => ({ ...item, historyExpanded: false }))];
    }

    handleRefresh() { 
        this.loadTimelineData(); 
    }

    handleHistoryToggle(event) {
        event.preventDefault();
        const clickedId = event.currentTarget.dataset.id;
        this.allItems = this.allItems.map(item => {
            if (item.id === clickedId) { return { ...item, historyExpanded: !item.historyExpanded }; }
            return item;
        });
    }

    handleTitleClick(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.recordId, actionName: 'view' }
        });
    }
}