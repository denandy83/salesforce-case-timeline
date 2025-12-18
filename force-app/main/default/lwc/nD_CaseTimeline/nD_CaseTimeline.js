// nd_CaseTimeline.js
import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTimelineData from '@salesforce/apex/ND_CaseTimelineController.getTimelineData';

export default class Nd_CaseTimeline extends NavigationMixin(LightningElement) {
    @track allItems = [];
    @track showEmail = true;
    @track showPublic = true;
    @track showInternal = true;
    @track showSystem = false;
    @track sortDirection = 'desc';
    @track isLoading = false;
    @track error;
    
    _recordId;
    _isTabVisible = true;
    _visibilityObserver = null;
    
    // Make recordId reactive - triggers loadTimelineData when it changes
    @api 
    get recordId() {
        return this._recordId;
    }
    
    set recordId(value) {
        this._recordId = value;
        // Auto-load when recordId is set or changes
        if (value) {
            this.loadTimelineData();
        }
    }

    // Load data when component connects (backup for first load)
    connectedCallback() {
        if (this.recordId) {
            this.loadTimelineData();
        }
        
        // Set up visibility detection - refresh when tab becomes visible
        this.setupVisibilityObserver();
    }
    
    disconnectedCallback() {
        // Clean up observer when component is removed
        if (this._visibilityObserver) {
            this._visibilityObserver.disconnect();
        }
    }
    
    
    setupVisibilityObserver() {
        // Use IntersectionObserver to detect when component becomes visible
        try {
            this._visibilityObserver = new IntersectionObserver((entries) => {
                entries.forEach(entry => {
                    const wasVisible = this._isTabVisible;
                    this._isTabVisible = entry.isIntersecting;
                    
                    // Refresh data when tab becomes visible (was hidden, now visible)
                    if (!wasVisible && this._isTabVisible && this.recordId) {
                        console.log('📱 Timeline tab became visible - refreshing data');
                        this.loadTimelineData();
                    }
                });
            }, {
                threshold: 0.1 // Trigger when at least 10% is visible
            });
            
            // Observe the component itself
            this._visibilityObserver.observe(this.template.host);
        } catch (error) {
            console.error('Error setting up visibility observer:', error);
        }
    }

    // Load timeline data imperatively (not cacheable)
    loadTimelineData() {
        if (!this.recordId) return;
        
        // Clear old data and show loading
        this.allItems = [];
        this.isLoading = true;
        this.error = undefined;
        
        console.log('🔄 Loading timeline data for case:', this.recordId);
        
        getTimelineData({ caseId: this.recordId })
            .then(data => {
                console.log('✅ Raw data from Apex:', data);
                console.log('📊 Number of items:', data.length);
                if (data.length > 0) {
                    console.log('📝 First item body:', data[0].body);
                }
                
                this.allItems = data.map(item => ({
                    ...item,
                    historyExpanded: false,
                    rowStyle: '', // Empty - let CSS handle styling
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
                
                console.log('✅ Mapped items:', this.allItems.length);
                
                // Force a render cycle to ensure renderedCallback fires
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                setTimeout(() => {
                    this.renderedCallback();
                }, 0);
            })
            .catch(error => {
                this.error = error;
                this.isLoading = false;
                console.error('Error fetching timeline:', error);
            });
    }

    // Render HTML content after view renders
    renderedCallback() {
        if (this.allItems && this.allItems.length > 0) {
            this.allItems.forEach(item => {
                const bodyContainer = this.template.querySelector(`[data-body-id="${item.id}"]`);
                if (bodyContainer && item.body) {
                    bodyContainer.innerHTML = item.body;
                    
                    // Add event listeners to copy buttons
                    const copyButtons = bodyContainer.querySelectorAll('.copy-btn');
                    copyButtons.forEach(btn => {
                        btn.addEventListener('click', this.handleCopyCode.bind(this));
                    });
                    
                    // Add event listeners to image preview links
                    const imageLinks = bodyContainer.querySelectorAll('.image-preview-link');
                    imageLinks.forEach(link => {
                        link.addEventListener('click', this.handleImagePreviewClick.bind(this));
                    });
                }
                
                if (item.historyExpanded && item.historyBody) {
                    const historyContainer = this.template.querySelector(`[data-history-id="${item.id}"]`);
                    if (historyContainer) {
                        historyContainer.innerHTML = item.historyBody;
                        
                        // Add event listeners to copy buttons in history
                        const copyButtons = historyContainer.querySelectorAll('.copy-btn');
                        copyButtons.forEach(btn => {
                            btn.addEventListener('click', this.handleCopyCode.bind(this));
                        });
                        
                        // Add event listeners to image preview links in history
                        const imageLinks = historyContainer.querySelectorAll('.image-preview-link');
                        imageLinks.forEach(link => {
                            link.addEventListener('click', this.handleImagePreviewClick.bind(this));
                        });
                    }
                }
            });
        }
    }
    
    handleCopyCode(event) {
        console.log('Copy button clicked!');
        const btn = event.target;
        const code = btn.getAttribute('data-code');
        console.log('Raw data-code:', code);
        const cleanCode = code ? code.replace(/\\n/g, '\n') : '';
        console.log('Clean code:', cleanCode);
        
        if (navigator.clipboard) {
            console.log('Using navigator.clipboard');
            navigator.clipboard.writeText(cleanCode).then(() => {
                console.log('Copy successful!');
                btn.textContent = 'Copied!';
                setTimeout(() => { btn.textContent = 'Copy'; }, 2000);
            }).catch((err) => {
                console.error('Copy failed:', err);
                btn.textContent = 'Error';
            });
        } else {
            console.log('Using execCommand fallback');
            // Fallback
            const temp = document.createElement('textarea');
            temp.value = cleanCode;
            temp.style.position = 'fixed';
            temp.style.left = '-999999px';
            document.body.appendChild(temp);
            temp.select();
            try {
                const success = document.execCommand('copy');
                console.log('execCommand result:', success);
                btn.textContent = 'Copied!';
                setTimeout(() => { btn.textContent = 'Copy'; }, 2000);
            } catch(e) {
                console.error('execCommand error:', e);
                btn.textContent = 'Error';
            }
            document.body.removeChild(temp);
        }
    }
    
    handleImagePreviewClick(event) {
        event.preventDefault();
        event.stopPropagation();
        
        const docId = event.currentTarget.dataset.docId;
        const recordType = event.currentTarget.dataset.recordType || 'ContentDocument';
        
        console.log('Image preview clicked - docId:', docId, 'recordType:', recordType);
        
        if (docId) {
            // Use NavigationMixin to open the file preview modal (same page, no new tab)
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: {
                    pageName: 'filePreview'
                },
                state: {
                    selectedRecordId: docId
                }
            });
        }
    }
    
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
    
    handleCollapseAll() {
        this.allItems = [...this.allItems.map(item => {
            return { ...item, historyExpanded: false };
        })];
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
        const recordId = event.currentTarget.dataset.recordId;
        
        // Navigate to the record page in a new Salesforce tab
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }
}