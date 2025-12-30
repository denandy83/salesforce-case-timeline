import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent'; 
import getTimelineData from '@salesforce/apex/ND_CaseTimelineController.getTimelineData';
import checkForNewItems from '@salesforce/apex/ND_CaseTimelineController.checkForNewItems';
import getTimelineConfig from '@salesforce/apex/ND_CaseTimelineController.getTimelineConfig';

export default class Nd_CaseTimeline extends NavigationMixin(LightningElement) {
    @track allItems = [];
    
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
    @track isSettingsOpen = false;
    configId;
    
    // Global toggle state (false = all collapsed initially)
    @track areAllExpanded = false;
    @track showAttachmentsCollapsed = true;
    @track useToastForUpdates = false;
    @track previewLines = 1;

    lastRefreshDate; 
    _pollingTimer;
    _recordId;
    
    // Config
    batchSize = 10;
    pollingInterval = 15000;
    debugMode = false;
    showLoadTimeToast = false;
    configLoaded = false;
    visibleCharLimit = 1950; 
    expandByDefault = false;


    @api 
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        if (value && this.configLoaded) this.initialLoad(); 
    }

    connectedCallback() {
        if (this.recordId) this.init(); 
    }

    disconnectedCallback() { this.stopPolling(); }

    async init() {
        try {
            this.isLoading = true;
            const config = await getTimelineConfig();
            this.configId = config.configId;
            this.batchSize = config.batchSize || 10;
            this.pollingInterval = config.pollingInterval || 15000;
            this.debugMode = config.debugMode;
            this.showLoadTimeToast = config.showToast;
            
            this.showEmail = config.defaultEmail;
            this.showPublic = config.defaultPublic;
            this.showInternal = config.defaultInternal;
            this.showSystem = config.defaultSystem;
            this.showAttachmentsCollapsed = config.showAttachmentsCollapsed;
            this.useToastForUpdates = config.useToastForUpdates;
            if (config.visibleCharLimit !== undefined && config.visibleCharLimit !== null) {
                this.visibleCharLimit = config.visibleCharLimit;
            }
            this.expandByDefault = config.expandByDefault;
            this.areAllExpanded = config.expandByDefault;
            this.previewLines = config.previewLines || 1;
            
            // Set initial sort direction based on config (default: desc = newest first)
            this.sortDirection = (config.newestFirst !== false) ? 'desc' : 'asc';
            
            if (this.showLoadTimeToast) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Configuration Loaded',
                        message: 'Active Config: ' + config.configName,
                        variant: 'info',
                        mode: 'dismissible'
                    })
                );
            }
            this.configLoaded = true;
            this.initialLoad();
        } catch (error) {
            console.error(error);
            this.configLoaded = true;
            this.initialLoad();
        }
    }

    // --- POLLING ---
    startPolling() {
        this.stopPolling(); 
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
                // CONDITIONAL LOGIC
                if (this.useToastForUpdates) {
                    // Option A: Show Standard Salesforce Toast
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Update Available',
                            message: 'New data received. Refresh the case to see it!',
                            variant: 'info',
                            mode: 'sticky' // 'sticky' ensures they see it until they dismiss it
                        })
                    );
                } else {
                    // Option B: Show Custom "Floating Toast" / Banner
                    this.isNewDataAvailable = true;
                }
                
                // Stop polling in both cases to prevent repeated notifications
                this.stopPolling();
            }
        }).catch(console.error);
    }

    // --- DATA LOADING ---
    initialLoad() {
        console.log('initialLoad called - recordId:', this.recordId, 'configLoaded:', this.configLoaded);
        if (!this.recordId || !this.configLoaded) return;
        this.stopPolling();
        this.isLoading = true;
        this.allItems = []; 
        console.log('Cleared allItems, sortDirection:', this.sortDirection);
        this.hasMoreItems = true;
        this.error = undefined;
        this.isNewDataAvailable = false;
        this.lastRefreshDate = new Date().toISOString();
        const startTime = performance.now();
        this.fetchData(null,startTime).then(() => {
            this.isLoading = false;
            console.log('Initial load complete, allItems count:', this.allItems.length);
            setTimeout(() => { this.renderedCallback(); this.startPolling(); }, 0);
        });
    }
    handleRefresh(event) {
        // Prevent default behavior if called from an anchor tag
        if (event) event.preventDefault();
        
        // Simply re-run the initial load logic
        this.initialLoad();
    }
    handleLoadMore() {
        if (!this.hasMoreItems || this.isLoadingMore) return;
        const lastItem = this.allItems[this.allItems.length - 1];
        const lastDate = lastItem ? lastItem.createdDate : null;
        
        const startTime = performance.now(); // Start Timer

        this.isLoadingMore = true;
        this.fetchData(lastDate, startTime).then(() => { // Pass Timer
            this.isLoadingMore = false;
            setTimeout(() => { this.renderedCallback(); }, 0);
        });
    }

    fetchData(referenceDate, startTime) {
        return getTimelineData({ 
            caseId: this.recordId, 
            referenceDate: referenceDate,
            limitSize: this.batchSize,
            sortDirection: this.sortDirection,
            debugMode: this.debugMode
        })
        .then(data => {
            console.log('Raw data received from Apex:', data ? data.length : 0, 'items');
            // --- NEW: Calculate Duration & Show Toast ---
            if (startTime && this.showLoadTimeToast) {
                const endTime = performance.now();
                const duration = Math.round(endTime - startTime);
                
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Data Loaded',
                        message: `Loaded ${data ? data.length : 0} items in ${duration}ms`,
                        variant: 'success',
                        mode: 'dismissible'
                    })
                );
            }
            // ---------------------------------------------

            if (!data || data.length < this.batchSize) this.hasMoreItems = false; 
            if (data && data.length > 0) {
                const processed = data.map(this.processItem.bind(this));
                console.log('Processed items:', processed.length);
                this.allItems = [...this.allItems, ...processed];
                console.log('Total allItems after adding:', this.allItems.length);
            } else {
                this.hasMoreItems = false;
            }
        }).catch(error => {
            this.error = error;
            this.isLoading = false;
            this.isLoadingMore = false;
        });
    }

    // --- PROCESS ITEM (The "Preview" Logic) ---
    processItem(item) {
        let processedItem = { ...item };

        // 1. Parse Email Content (Hybrid Split/DOM approach)
        if (processedItem.category === 'Email') {
            const parsed = this.parseEmailContent(processedItem.body);
            processedItem.body = parsed.newContent;
            processedItem.historyBody = parsed.historyContent;
            processedItem.hasHistory = parsed.hasHistory;
        }

        // 2. Create Plain Text Preview
        let previewText = '';
        if (!processedItem.isSystemCategory && processedItem.body) {
            const tempDiv = document.createElement('div');
            tempDiv.innerHTML = processedItem.body;
            const fullText = tempDiv.innerText || '';
            
            // CLEANER: Replace newlines with spaces so text flows into the multi-line block
            const cleanText = fullText.replace(/\s+/g, ' ').trim();
            
            if (cleanText.length > 0) {
                // Grab enough text to fill ~3-4 lines (400 chars is plenty safe)
                // The CSS will handle the actual cutting off visually.
                previewText = cleanText.substring(0, 400); 
            } else {
                previewText = 'Click to view content...';
            }
        }

        // DYNAMIC CSS: Create the clamp style based on the user setting
        const lineClampStyle = `
            display: -webkit-box; 
            -webkit-line-clamp: ${this.previewLines}; 
            -webkit-box-orient: vertical; 
            overflow: hidden; 
            text-overflow: ellipsis;
        `;

        return {
            ...processedItem,
            isExpanded: this.expandByDefault,
            historyExpanded: false, // Default history hidden
            previewText: previewText,
            previewStyle: lineClampStyle,
            rowStyle: '',
            boxClass: processedItem.isInternal 
                ? 'slds-box slds-box_x-small slds-m-bottom_small internal-note'
                : 'slds-box slds-box_x-small slds-m-bottom_small',
            emailBadgeClass: processedItem.isOutgoing 
                ? 'slds-badge outgoing-email-badge'
                : 'slds-badge slds-theme_success',
            isEmailCategory: processedItem.category === 'Email',
            isPublicCategory: processedItem.category === 'Public',
            isInternalCategory: processedItem.category === 'Internal',
            isSystemCategory: processedItem.category === 'System',
            showEmailInfo: false, // Initialize email info popover as closed
            // Icons
            expandIcon: 'utility:chevronright'
        };
    }

    // --- PARSING LOGIC ---
    parseEmailContent(fullBody) {
        if (!fullBody) return { newContent: '', historyContent: '', hasHistory: false };

        // NEW: If 0, use total length (disable truncation). Otherwise use config.
        const maxChars = (this.visibleCharLimit === 0) ? fullBody.length + 100 : this.visibleCharLimit;

        const xmlTagRegex = new RegExp('<\\?xml[\\s\\S]*?\\?>', 'gi');
        let cleaned = fullBody
            .replace(/<head[^>]*>[\s\S]*?<\/head>/gi, '')
            .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
            .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
            .replace(xmlTagRegex, '')
            .replace(/<\/?o:[^>]*>/gi, '')
            .replace(/<\/?v:[^>]*>/gi, '')
            .replace(/<\/?w:[^>]*>/gi, '');

        const htmlSplitIndex = this.findSplitIndex(cleaned);
        let useNaturalSplit = false;

        if (htmlSplitIndex > 0) {
            const contentBeforeSplit = cleaned.substring(0, htmlSplitIndex);
            const tempDiv = document.createElement('div');
            tempDiv.innerHTML = contentBeforeSplit;
            // Check against dynamic maxChars
            if (tempDiv.innerText.length <= maxChars) {
                useNaturalSplit = true;
            }
        }

        if (useNaturalSplit) {
            const newContent = cleaned.substring(0, htmlSplitIndex);
            const historyContent = cleaned.substring(htmlSplitIndex);
            return { 
                newContent: this.linkify(newContent), 
                historyContent: historyContent, 
                hasHistory: true 
            };
        } else {
            // Pass dynamic maxChars to truncateHtml
            return this.truncateHtml(cleaned, '', maxChars);
        }
    }

    findSplitIndex(html) {
        const patterns = [
            /On\s+[A-Za-z]{3}[\s\S]{0,200}?wrote:/i,
            /-{3,}\s*(Original|Forwarded)\s+Message\s*-{3,}/i,
            /(?:From:|<b>From:<\/b>)[\s\S]{1,300}?(?:Sent:|<b>Sent:<\/b>)/i,
            /From:.{1,100}?(&lt;|<).+?@.+?(&gt;|>)/i,
            /De\s*:.{1,100}?Envoy.{1,100}?:/i,
            /Da\s*:.{1,100}?Inviato\s*:/i, // Italian: Da: ... Inviato:
            ///<div class="gmail_quote">/i,
            /_{20,}/
        ];

        let bestIndex = -1;
        for (let pattern of patterns) {
            const match = pattern.exec(html);
            if (match) {
                if (bestIndex === -1 || match.index < bestIndex) {
                    bestIndex = match.index;
                }
            }
        }

        if (bestIndex !== -1) {
            const lastClose = html.lastIndexOf('>', bestIndex);
            if (lastClose !== -1 && (bestIndex - lastClose) < 100) {
                return lastClose + 1;
            }
            return bestIndex;
        }
        return -1;
    }

    truncateHtml(html, existingHistory, maxChars) {
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const body = doc.body;

        if (body.innerText.length <= maxChars) {
            return { newContent: this.linkify(html), historyContent: existingHistory, hasHistory: !!existingHistory };
        }

        const headRoot = document.createElement('div');
        const tailRoot = document.createElement('div');
        let charCount = 0;
        let limitReached = false;

        function processNode(sourceNode, headParent, tailParent) {
            if (sourceNode.nodeType === Node.TEXT_NODE) {
                const text = sourceNode.textContent;
                if (limitReached) {
                    tailParent.appendChild(sourceNode.cloneNode(true));
                    return;
                }
                if (charCount + text.length <= maxChars) {
                    headParent.appendChild(sourceNode.cloneNode(true));
                    charCount += text.length;
                } else {
                    const remainingSpace = maxChars - charCount;
                    headParent.appendChild(document.createTextNode(text.substring(0, remainingSpace)));
                    tailParent.appendChild(document.createTextNode(text.substring(remainingSpace)));
                    charCount = maxChars;
                    limitReached = true;
                }
            } else if (sourceNode.nodeType === Node.ELEMENT_NODE) {
                const headClone = sourceNode.cloneNode(false);
                const tailClone = sourceNode.cloneNode(false);
                let hasHead = false, hasTail = false;

                for (let child of sourceNode.childNodes) {
                    processNode(child, headClone, tailClone);
                    if (headClone.lastChild) hasHead = true;
                    if (tailClone.lastChild) hasTail = true;
                }
                if (hasHead) headParent.appendChild(headClone);
                if (hasTail) tailParent.appendChild(tailClone);
            }
        }

        for (let child of body.childNodes) {
            processNode(child, headRoot, tailRoot);
        }

        const newContentHtml = headRoot.innerHTML + '...';
        const overflowHtml = tailRoot.innerHTML;
        const finalHistory = (overflowHtml + (existingHistory ? '<br/><hr/>' + existingHistory : ''));

        return { 
            newContent: this.linkify(newContentHtml), 
            historyContent: finalHistory, 
            hasHistory: true 
        };
    }

    linkify(html) {
        if (!html) return '';
        
        // 1. Parse HTML
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        
        // 2. TreeWalker to find text nodes NOT inside <a> tags
        const walker = document.createTreeWalker(
            doc.body, 
            NodeFilter.SHOW_TEXT, 
            {
                acceptNode: function(node) {
                    // Skip if parent is already an anchor <a> tag
                    if (node.parentElement && node.parentElement.tagName === 'A') {
                        return NodeFilter.FILTER_REJECT;
                    }
                    // Skip script/style tags
                    if (node.parentElement && (node.parentElement.tagName === 'SCRIPT' || node.parentElement.tagName === 'STYLE')) {
                        return NodeFilter.FILTER_REJECT;
                    }
                    return NodeFilter.FILTER_ACCEPT;
                }
            }, 
            false
        );

        const nodesToReplace = [];
        let currentNode;
        
        // 3. Collect nodes (can't modify while walking)
        while (currentNode = walker.nextNode()) {
            if (currentNode.nodeValue && currentNode.nodeValue.match(/(\b(https?|ftp):\/\/[-A-Z0-9+&@#\/%?=~_|!:,.;]*[-A-Z0-9+&@#\/%=~_|])/i)) {
                nodesToReplace.push(currentNode);
            }
        }

        // 4. Replace text with links
        const urlPattern = /(\b(https?|ftp):\/\/[-A-Z0-9+&@#\/%?=~_|!:,.;]*[-A-Z0-9+&@#\/%=~_|])/gim;
        
        nodesToReplace.forEach(node => {
            const fragment = document.createDocumentFragment();
            const parts = node.nodeValue.split(urlPattern);
            
            // Regex split creates groups; we rebuild elements
            let currentText = '';
            
            // The split with capturing groups returns: [text, url, protocol, text, ...]
            // We need to carefully reconstruct
            const newSpan = document.createElement('span');
            newSpan.innerHTML = node.nodeValue.replace(urlPattern, '<a href="$1" target="_blank" style="color:#0176d3;">$1</a>');
            
            node.parentNode.replaceChild(newSpan, node);
        });

        return doc.body.innerHTML;
    }

    // --- INTERACTION HANDLERS ---

    // 1. Toggle Single Item
    handleTitleClick(event) {
        event.preventDefault();
        const clickedId = event.currentTarget.dataset.recordId;
        this.allItems = this.allItems.map(item => {
            if (item.id === clickedId) {
                const isNowExpanded = !item.isExpanded;
                return { 
                    ...item, 
                    isExpanded: isNowExpanded,
                    expandIcon: isNowExpanded ? 'utility:chevrondown' : 'utility:chevronright'
                };
            }
            return item;
        });
        // Wait for DOM update to render body
        setTimeout(() => { this.renderedCallback(); }, 0);
    }
    
    

    // 3. Toggle All (Global Button)
    handleExpandCollapseAll() {
        this.areAllExpanded = !this.areAllExpanded;
        const icon = this.areAllExpanded ? 'utility:chevrondown' : 'utility:chevronright';
        
        this.allItems = this.allItems.map(item => ({ 
            ...item, 
            isExpanded: this.areAllExpanded,
            expandIcon: icon
        }));
        
        setTimeout(() => { this.renderedCallback(); }, 0);
    }

    handleHistoryToggle(event) {
        event.preventDefault();
        const clickedId = event.currentTarget.dataset.id;
        this.allItems = this.allItems.map(item => {
            if (item.id === clickedId) { return { ...item, historyExpanded: !item.historyExpanded }; }
            return item;
        });
        setTimeout(() => { this.renderedCallback(); }, 0);
    }

    renderedCallback() {
        if (this.filteredData && this.filteredData.length > 0) {
            this.filteredData.forEach(item => {
                
                // 1. EXPANDED VIEW (Always show attachments if expanded)
                if (item.isExpanded) {
                    const bodyContainer = this.template.querySelector(`[data-body-id="${item.id}"]`);
                    if (bodyContainer && item.body && !bodyContainer.innerHTML) {
                        bodyContainer.innerHTML = item.body;
                        this.attachEventListeners(bodyContainer);
                    }
                    
                    // Inject recipient HTML for expanded email view
                    if (item.isEmailCategory) {
                        const toContainer = this.template.querySelector(`[data-expanded-to="${item.id}"]`);
                        if (toContainer && item.emailTo && !toContainer.innerHTML) {
                            toContainer.innerHTML = item.emailTo;
                            this.attachEventListeners(toContainer);
                        }
                        const ccContainer = this.template.querySelector(`[data-expanded-cc="${item.id}"]`);
                        if (ccContainer && item.emailCc && !ccContainer.innerHTML) {
                            ccContainer.innerHTML = item.emailCc;
                            this.attachEventListeners(ccContainer);
                        }
                        const bccContainer = this.template.querySelector(`[data-expanded-bcc="${item.id}"]`);
                        if (bccContainer && item.emailBcc && !bccContainer.innerHTML) {
                            bccContainer.innerHTML = item.emailBcc;
                            this.attachEventListeners(bccContainer);
                        }
                    }
                    
                    if (item.historyExpanded && item.historyBody) {
                        const historyContainer = this.template.querySelector(`[data-history-id="${item.id}"]`);
                        if (historyContainer && !historyContainer.innerHTML) {
                            historyContainer.innerHTML = item.historyBody;
                            this.attachEventListeners(historyContainer);
                        }
                    }
                    const attachContainer = this.template.querySelector(`[data-attachments-id="${item.id}"]`);
                    if (attachContainer && item.attachmentsHtml && !attachContainer.innerHTML) {
                        attachContainer.innerHTML = item.attachmentsHtml;
                        this.attachEventListeners(attachContainer);
                    }
                } 
                
                // 2. COLLAPSED VIEW (Conditional based on Config)
                else if (this.showAttachmentsCollapsed) { // <--- CHECK CONFIG HERE
                    const collapsedAttachContainer = this.template.querySelector(`[data-attachments-collapsed-id="${item.id}"]`);
                    if (collapsedAttachContainer && item.attachmentsHtml && !collapsedAttachContainer.innerHTML) {
                        collapsedAttachContainer.innerHTML = item.attachmentsHtml;
                        this.attachEventListeners(collapsedAttachContainer);
                        
                        // Prevent row expansion when clicking the file
                        collapsedAttachContainer.addEventListener('click', (e) => {
                            e.stopPropagation();
                        });
                    }
                }
                
                // 3. POPOVER - Inject recipient HTML when popover is visible
                if (item.showEmailInfo && item.isEmailCategory) {
                    const popoverToContainer = this.template.querySelector(`[data-popover-to="${item.id}"]`);
                    if (popoverToContainer && item.emailTo && !popoverToContainer.innerHTML) {
                        popoverToContainer.innerHTML = item.emailTo;
                        this.attachEventListeners(popoverToContainer);
                    }
                    const popoverCcContainer = this.template.querySelector(`[data-popover-cc="${item.id}"]`);
                    if (popoverCcContainer && item.emailCc && !popoverCcContainer.innerHTML) {
                        popoverCcContainer.innerHTML = item.emailCc;
                        this.attachEventListeners(popoverCcContainer);
                    }
                    const popoverBccContainer = this.template.querySelector(`[data-popover-bcc="${item.id}"]`);
                    if (popoverBccContainer && item.emailBcc && !popoverBccContainer.innerHTML) {
                        popoverBccContainer.innerHTML = item.emailBcc;
                        this.attachEventListeners(popoverBccContainer);
                    }
                    const popoverFromContainer = this.template.querySelector(`[data-popover-from="${item.id}"]`);
                    if (popoverFromContainer && item.emailFrom && !popoverFromContainer.innerHTML) {
                        popoverFromContainer.innerHTML = item.emailFrom;
                        this.attachEventListeners(popoverFromContainer);
                    }
                }
            });
        }
    }
    
    attachEventListeners(container) {
       if(!container) return;
       container.querySelectorAll('.copy-btn').forEach(btn => btn.addEventListener('click', this.handleCopyCode.bind(this)));
       container.querySelectorAll('.image-preview-link').forEach(link => link.addEventListener('click', this.handleImagePreviewClick.bind(this)));
       container.querySelectorAll('.mention-link').forEach(link => link.addEventListener('click', this.handleMentionClick.bind(this)));
       container.querySelectorAll('.email-recipient-link').forEach(link => link.addEventListener('click', this.handleRecipientClick.bind(this)));
    }
    
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
        event.preventDefault(); 
        event.stopPropagation();
        
        const docId = event.currentTarget.dataset.docId;

        // CHECK ID PREFIX
        // '00P' is the key prefix for Legacy Attachments. 
        // These CANNOT use the 'filePreview' page type.
        if (docId && docId.startsWith('00P')) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: docId,
                    objectApiName: 'Attachment',
                    actionName: 'view'
                }
            });
        } 
        // '069' is ContentDocument (Files). These look great in 'filePreview'.
        else {
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: { pageName: 'filePreview' },
                state: { selectedRecordId: docId }
            });
        }
    }

    handleMentionClick(event) {
        event.preventDefault(); event.stopPropagation();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: event.currentTarget.dataset.recordId, actionName: 'view' }
        });
    }

    handleRecipientClick(event) {
        event.preventDefault(); 
        event.stopPropagation();
        const recordId = event.currentTarget.dataset.recordId;
        
        // Navigate to the record - will open in subtab in console
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { 
                recordId: recordId, 
                actionName: 'view' 
            }
        });
    }

    // GETTERS
    get sortIcon() { return this.sortDirection === 'desc' ? 'utility:arrowdown' : 'utility:arrowup'; }
    get sortLabel() { return this.sortDirection === 'desc' ? 'Newest First' : 'Oldest First'; }
    get expandCollapseLabel() { return this.areAllExpanded ? 'Collapse All' : 'Expand All'; }
    get expandCollapseIcon() { return this.areAllExpanded ? 'utility:collapse_all' : 'utility:expand_all'; }
    
    get hasData() { return this.filteredData && this.filteredData.length > 0; }
    get emailLabel() { return `Emails (${this.allItems.filter(i => i.category === 'Email').length})`; }
    get publicLabel() { return `Public (${this.allItems.filter(i => i.category === 'Public').length})`; }
    get internalLabel() { return `Internal (${this.allItems.filter(i => i.category === 'Internal').length})`; }
    get systemLabel() { return `System (${this.allItems.filter(i => i.category === 'System').length})`; }

    get filteredData() {
        let result = this.allItems.filter(item => {
            if (item.category === 'Email' && this.showEmail) return true;
            if (item.category === 'Public' && this.showPublic) return true;
            if (item.category === 'Internal' && this.showInternal) return true;
            if (item.category === 'System' && this.showSystem) return true;
            return false;
        });
        // No need to sort - data comes from server in the correct order
        return result;
    }

    handleToggle(event) {
        const name = event.target.name;
        const checked = event.target.checked;
        if (name === 'email') this.showEmail = checked;
        if (name === 'public') this.showPublic = checked;
        if (name === 'internal') this.showInternal = checked;
        if (name === 'system') this.showSystem = checked;
    }

    handleSortToggle() {
        const oldDirection = this.sortDirection;
        this.sortDirection = this.sortDirection === 'desc' ? 'asc' : 'desc';
        console.log('Sort toggled from', oldDirection, 'to', this.sortDirection);
        // Reload data to get items in the new sort order
        this.initialLoad();
    }
    handleCollapseAll() { this.allItems = [...this.allItems.map(item => ({ ...item, historyExpanded: false }))]; }
    handleHistoryToggle(event) {
        event.preventDefault();
        const clickedId = event.currentTarget.dataset.id;
        this.allItems = this.allItems.map(item => {
            if (item.id === clickedId) { return { ...item, historyExpanded: !item.historyExpanded }; }
            return item;
        });
    }
    // 1. Toggle Expand/Collapse (Attached to the main box/title)
    handleTitleClick(event) {
        event.preventDefault();
        const clickedId = event.currentTarget.dataset.recordId;
        
        this.allItems = this.allItems.map(item => {
            if (item.id === clickedId) {
                const isNowExpanded = !item.isExpanded;
                return { 
                    ...item, 
                    isExpanded: isNowExpanded,
                    expandIcon: isNowExpanded ? 'utility:chevrondown' : 'utility:chevronright'
                };
            }
            return item;
        });
        
        // Wait for render to inject HTML into the newly expanded body
        setTimeout(() => { this.renderedCallback(); }, 0);
    }
    
    // 2. Open Record (Attached to the 'New Window' icon)
    handleOpenRecord(event) {
        // Prevent the click from bubbling up to the main box (which would toggle expand)
        event.preventDefault(); 
        event.stopPropagation(); 
        
        // Perform Navigation
        this[NavigationMixin.Navigate]({ 
            type: 'standard__recordPage', 
            attributes: { recordId: event.currentTarget.dataset.recordId, actionName: 'view' } 
        });
    }
    handleSettingsClick() {
        this.isSettingsOpen = true;
    }

    handleModalClose() {
        this.isSettingsOpen = false;
    }

    handleSettingsSuccess() {
        this.isSettingsOpen = false;
        
        // Show success toast
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Configuration saved. Reloading timeline...',
                variant: 'success'
            })
        );

        // Reload the component to apply new settings
        this.isLoading = true;
        this.configLoaded = false; // Force full config re-fetch
        this.init();
    }

    handleEmailInfoToggle(event) {
        event.preventDefault();
        event.stopPropagation();
        const itemId = event.currentTarget.dataset.id;
        
        // Toggle the visibility by updating the item in allItems
        this.allItems = this.allItems.map(item => {
            if (item.id === itemId) {
                return { ...item, showEmailInfo: !item.showEmailInfo };
            }
            return item;
        });
    }

    handleEmailInfoClose(event) {
        event.preventDefault();
        event.stopPropagation();
        const itemId = event.currentTarget.dataset.id;
        
        // Close the popover
        this.allItems = this.allItems.map(item => {
            if (item.id === itemId) {
                return { ...item, showEmailInfo: false };
            }
            return item;
        });
    }
}