import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent'; //
import getTimelineData from '@salesforce/apex/ND_CaseTimelineController.getTimelineData';
import checkForNewItems from '@salesforce/apex/ND_CaseTimelineController.checkForNewItems';
import getTimelineConfig from '@salesforce/apex/ND_CaseTimelineController.getTimelineConfig'; // Import new method

export default class Nd_CaseTimeline extends NavigationMixin(LightningElement) {
    @track allItems = [];
    
    // Default values (will be overwritten by config)
    @track showEmail = true;
    @track showPublic = true;
    @track showInternal = true;
    @track showSystem = false;
    @track sortDirection = 'desc';
    
    @track isLoading = false;
    @track isLoadingMore = false; 
    @track error;
    
    @track isNewDataAvailable = false;
    @track hasMoreItems = true; 
    
    lastRefreshDate; 
    _pollingTimer;
    _recordId;
    
    // --- DYNAMIC CONFIG VARIABLES ---
    batchSize = 10;         // Fallback default
    pollingInterval = 15000; // Fallback default
    debugMode = false;
    showLoadTimeToast = false;
    configLoaded = false;    // Guard to ensure we don't fetch data before config

    @api 
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        // Only trigger load if we have the ID. 
        // If config isn't loaded yet, connectedCallback will handle it.
        if (value && this.configLoaded) { 
            this.initialLoad(); 
        }
    }

    connectedCallback() {
        if (this.recordId) { 
            this.init(); // New init orchestration
        }
    }

    disconnectedCallback() { this.stopPolling(); }

    // --- INITIALIZATION ---
    
    async init() {
        try {
            this.isLoading = true;
            // 1. Fetch Configuration
            const config = await getTimelineConfig();
            
            // 2. Apply Configuration
            this.batchSize = config.batchSize || 10;
            this.pollingInterval = config.pollingInterval || 15000; // Apex handles the *1000 conversion if you did it there, or do it here.
            this.debugMode = config.debugMode;
            this.showLoadTimeToast = config.showToast;
            
            // Apply checkbox defaults
            this.showEmail = config.defaultEmail;
            this.showPublic = config.defaultPublic;
            this.showInternal = config.defaultInternal;
            this.showSystem = config.defaultSystem;
            
            this.logDebug('Configuration Loaded', config);
            this.configLoaded = true;
            
            // 3. Start Data Load
            this.initialLoad();
            
        } catch (error) {
            console.error('Error loading config', error);
            // Fallback: load anyway with defaults
            this.configLoaded = true;
            this.initialLoad();
        }
    }

    // --- POLLING ---
    
    startPolling() {
        this.stopPolling(); 
        this.logDebug(`Starting Polling (Interval: ${this.pollingInterval}ms)`);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._pollingTimer = setInterval(() => { this.checkServerForUpdates(); }, this.pollingInterval);
    }

    stopPolling() {
        if (this._pollingTimer) { clearInterval(this._pollingTimer); this._pollingTimer = null; }
    }

    checkServerForUpdates() {
        if (!this.recordId || !this.lastRefreshDate) return;
        checkForNewItems({ caseId: this.recordId, lastCheckDate: this.lastRefreshDate })
        .then(hasNewData => {
            if (hasNewData) {
                this.logDebug('New data detected via polling');
                this.isNewDataAvailable = true;
                this.stopPolling();
            }
        })
        .catch(console.error);
    }

    // --- DATA LOADING ---

    initialLoad() {
        if (!this.recordId || !this.configLoaded) return;
        
        this.stopPolling();
        this.isLoading = true;
        this.allItems = []; 
        this.hasMoreItems = true;
        this.error = undefined;
        this.isNewDataAvailable = false;
        
        this.lastRefreshDate = new Date().toISOString();

        // 1. Measure Start Time
        const startTime = performance.now();

        this.fetchData(null)
            .then(() => {
                // 2. Measure End Time
                const endTime = performance.now();
                const duration = Math.round(endTime - startTime);
                
                this.isLoading = false;
                
                // 3. Show Toast if Configured
                if (this.showLoadTimeToast) {
                    this.showToastMessage('Success', `Timeline loaded in ${duration}ms`, 'success');
                }

                setTimeout(() => { 
                    this.renderedCallback(); 
                    this.startPolling(); 
                }, 0);
            });
    }

    handleLoadMore() {
        if (!this.hasMoreItems || this.isLoadingMore) return;
        
        const lastItem = this.allItems[this.allItems.length - 1];
        const lastDate = lastItem ? lastItem.createdDate : null;

        this.isLoadingMore = true;
        const startTime = performance.now();

        this.fetchData(lastDate)
            .then(() => {
                const endTime = performance.now();
                const duration = Math.round(endTime - startTime);
                
                this.isLoadingMore = false;
                
                if (this.showLoadTimeToast) {
                    this.showToastMessage('Success', `More items loaded in ${duration}ms`, 'success');
                }

                setTimeout(() => { this.renderedCallback(); }, 0);
            });
    }

    fetchData(beforeDate) {
        this.logDebug(`Fetching data. Limit: ${this.batchSize}, Before: ${beforeDate}`);
        
        return getTimelineData({ 
            caseId: this.recordId, 
            beforeDate: beforeDate,
            limitSize: this.batchSize // Use dynamic batch size
        })
        .then(data => {
            if (!data || data.length < this.batchSize) {
                this.hasMoreItems = false; 
            }
            
            if (data && data.length > 0) {
                const processed = data.map(this.processItem.bind(this)); // Bind this for context if needed
                this.allItems = [...this.allItems, ...processed];
                this.logDebug(`Loaded ${data.length} items`);
            } else {
                this.hasMoreItems = false;
            }
        })
        .catch(error => {
            this.error = error;
            this.isLoading = false;
            this.isLoadingMore = false;
            console.error(error);
        });
    }

    // --- HELPER FUNCTIONS ---

    logDebug(message, data) {
        if (this.debugMode) {
            if (data) {
                console.log(`[ND_Timeline DEBUG] ${message}`, data);
            } else {
                console.log(`[ND_Timeline DEBUG] ${message}`);
            }
        }
    }

    showToastMessage(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    // Helper to format a single item (Unchanged logic, just binding)
    processItem(item) {
        return {
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
        };
    }

    // --- STANDARD UI HANDLERS (Same as before) ---
    
    handleRefresh() { this.initialLoad(); }

    renderedCallback() {
        // ... (Keep your existing renderedCallback logic exactly as is) ...
        if (this.filteredData && this.filteredData.length > 0) {
            this.filteredData.forEach(item => {
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
       // ... (Keep existing logic) ...
       container.querySelectorAll('.copy-btn').forEach(btn => btn.addEventListener('click', this.handleCopyCode.bind(this)));
       container.querySelectorAll('.image-preview-link').forEach(link => link.addEventListener('click', this.handleImagePreviewClick.bind(this)));
       container.querySelectorAll('.mention-link').forEach(link => link.addEventListener('click', this.handleMentionClick.bind(this)));
    }
    
    // ... (Keep handleCopyCode, handleImagePreviewClick, handleMentionClick, Getters, handleToggle, etc.) ...
    
    handleCopyCode(event) {
        const btn = event.target;
        
        // 1. Find the wrapper parent
        const wrapper = btn.closest('.code-wrapper');
        
        // 2. Find the hidden textarea sibling
        const hiddenTextarea = wrapper.querySelector('.raw-code-storage');
        
        // 3. Get the value (The browser automatically handles decoding entities like &lt;)
        const cleanCode = hiddenTextarea ? hiddenTextarea.value : '';

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

    // Getters
    get sortIcon() { return this.sortDirection === 'desc' ? 'utility:arrowdown' : 'utility:arrowup'; }
    get sortLabel() { return this.sortDirection === 'desc' ? 'Newest First' : 'Oldest First'; }
    get hasData() { return this.filteredData && this.filteredData.length > 0; }
    // --- DYNAMIC LABEL GETTERS ---
    get emailLabel() {
        const count = this.allItems ? this.allItems.filter(item => item.category === 'Email').length : 0;
        return `Emails (${count})`;
    }
    get publicLabel() {
        const count = this.allItems ? this.allItems.filter(item => item.category === 'Public').length : 0;
        return `Public (${count})`;
    }
    get internalLabel() {
        const count = this.allItems ? this.allItems.filter(item => item.category === 'Internal').length : 0;
        return `Internal (${count})`;
    }
    get systemLabel() {
        const count = this.allItems ? this.allItems.filter(item => item.category === 'System').length : 0;
        return `System (${count})`;
    }
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
    handleCollapseAll() { this.allItems = [...this.allItems.map(item => ({ ...item, historyExpanded: false }))]; }
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
        this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId: event.currentTarget.dataset.recordId, actionName: 'view' } });
    }
}