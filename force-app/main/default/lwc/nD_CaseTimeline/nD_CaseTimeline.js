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
        this.setupVisibilityObserver();
    }

    disconnectedCallback() {
        if (this._visibilityObserver) {
            this._visibilityObserver.disconnect();
        }
    }

    setupVisibilityObserver() {
        try {
            this._visibilityObserver = new IntersectionObserver((entries) => {
                entries.forEach(entry => {
                    const wasVisible = this._isTabVisible;
                    this._isTabVisible = entry.isIntersecting;
                    
                    if (!wasVisible && this._isTabVisible && this.recordId) {
                        this.loadTimelineData();
                    }
                });
            }, {
                threshold: 0.1
            });
            
            this._visibilityObserver.observe(this.template.host);
        } catch (error) {
            console.error('Error setting up visibility observer:', error);
        }
    }

    loadTimelineData() {
        if (!this.recordId) return;
        
        this.allItems = [];
        this.isLoading = true;
        this.error = undefined;
        
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
                
                setTimeout(() => {
                    this.renderedCallback();
                }, 0);
            })
            .catch(error => {
                this.error = error;
                this.isLoading = false;
            });
    }

    renderedCallback() {
        if (this.allItems && this.allItems.length > 0) {
            this.allItems.forEach(item => {
                const bodyContainer = this.template.querySelector(`[data-body-id="${item.id}"]`);
                if (bodyContainer && item.body) {
                    bodyContainer.innerHTML = item.body;
                    
                    const copyButtons = bodyContainer.querySelectorAll('.copy-btn');
                    copyButtons.forEach(btn => {
                        btn.addEventListener('click', this.handleCopyCode.bind(this));
                    });
                    
                    const imageLinks = bodyContainer.querySelectorAll('.image-preview-link');
                    imageLinks.forEach(link => {
                        link.addEventListener('click', this.handleImagePreviewClick.bind(this));
                    });
                    
                    const mentionLinks = bodyContainer.querySelectorAll('.mention-link');
                    mentionLinks.forEach(link => {
                        link.addEventListener('click', this.handleMentionClick.bind(this));
                    });
                }
                
                if (item.historyExpanded && item.historyBody) {
                    const historyContainer = this.template.querySelector(`[data-history-id="${item.id}"]`);
                    if (historyContainer) {
                        historyContainer.innerHTML = item.historyBody;
                        
                        const copyButtons = historyContainer.querySelectorAll('.copy-btn');
                        copyButtons.forEach(btn => {
                            btn.addEventListener('click', this.handleCopyCode.bind(this));
                        });
                        
                        const imageLinks = historyContainer.querySelectorAll('.image-preview-link');
                        imageLinks.forEach(link => {
                            link.addEventListener('click', this.handleImagePreviewClick.bind(this));
                        });
                        
                        const mentionLinks = historyContainer.querySelectorAll('.mention-link');
                        mentionLinks.forEach(link => {
                            link.addEventListener('click', this.handleMentionClick.bind(this));
                        });
                    }
                }
            });
        }
    }

    handleCopyCode(event) {
        const btn = event.target;
        const code = btn.getAttribute('data-code');
        const cleanCode = code ? code.replace(/\\n/g, '\n') : '';
        
        if (navigator.clipboard) {
            navigator.clipboard.writeText(cleanCode).then(() => {
                btn.textContent = 'Copied!';
                setTimeout(() => { btn.textContent = 'Copy'; }, 2000);
            }).catch(() => {
                btn.textContent = 'Error';
            });
        } else {
            const temp = document.createElement('textarea');
            temp.value = cleanCode;
            temp.style.position = 'fixed';
            temp.style.left = '-999999px';
            document.body.appendChild(temp);
            temp.select();
            try {
                document.execCommand('copy');
                btn.textContent = 'Copied!';
                setTimeout(() => { btn.textContent = 'Copy'; }, 2000);
            } catch(e) {
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
        
        if (docId) {
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

    handleMentionClick(event) {
        event.preventDefault();
        event.stopPropagation();
        
        const recordId = event.currentTarget.dataset.recordId;
        
        if (recordId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    actionName: 'view'
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
        
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        });
    }
}