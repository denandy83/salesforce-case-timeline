import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent'; 
import getTimelineData from '@salesforce/apex/ND_CaseTimelineController.getTimelineData';
import checkForNewItems from '@salesforce/apex/ND_CaseTimelineController.checkForNewItems';
import getTimelineConfig from '@salesforce/apex/ND_CaseTimelineController.getTimelineConfig';
import getTimelineCounts from '@salesforce/apex/ND_CaseTimelineController.getTimelineCounts';
import addComment from '@salesforce/apex/ND_CaseTimelineController.addComment';
import getEmailHistory from '@salesforce/apex/ND_CaseTimelineController.getEmailHistory';
import getFiles from '@salesforce/apex/ND_CaseTimelineController.getFiles';

export default class Nd_CaseTimeline extends NavigationMixin(LightningElement) {
    @track allItems = [];
    
    @track totalEmailCount = 0;
    @track totalPublicCount = 0;
    @track totalInternalCount = 0;
    @track totalSystemCount = 0;

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

    // Files state
    @track showFiles = false;
    @track allFiles = [];
    @track fileSearchKey = '';
    @track draftFileSearchKey = '';
    @track fileSortBy = 'createdDate';
    @track fileSortDirection = 'desc';
    @track showUniqueFiles = true;
    @track isFilesLoading = false;
    @track isFilesLoadingMore = false;
    @track hasMoreFiles = false; // Bug 1: Init to false to prevent button pop-in
    @track isFilesInitialized = false; // Bug 1: Track if we have finished first load
    fileLimit = 50;
    fileOffset = 0;
    _searchTimer;

    get isManualSearch() {
        // Bug 1: Only show search button after initialization
        return this.isFilesInitialized && (this.hasMoreFiles || (this.allFiles && this.allFiles.length > 50));
    }

    get fileSearchPlaceholder() {
        const count = this.allFiles ? this.allFiles.length : 0;
        const suffix = this.hasMoreFiles ? '+' : '';
        return `Search ${count}${suffix} files by filename or filetype (e.g. .png, myFile)...`;
    }

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

    _observer; // Infinite scroll observer

    fileColumns = [
        { 
            label: 'Filename', 
            fieldName: 'fullName', 
            sortable: true,
            type: 'button',
            typeAttributes: {
                label: { fieldName: 'fullName' },
                name: 'open_file',
                variant: 'base',
                class: 'slds-text-link'
            }
        },
        { label: 'Creation Date', fieldName: 'createdDate', type: 'date', sortable: true, typeAttributes: { year: 'numeric', month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' } },
        { label: 'Filetype', fieldName: 'fileType', sortable: true },
        { label: 'Size', fieldName: 'formattedSize', sortable: true, cellAttributes: { alignment: 'left' } },
        { label: 'Owner', fieldName: 'ownerName', sortable: true }
    ];


    @api 
    get recordId() { return this._recordId; }
    set recordId(value) {
        this._recordId = value;
        if (value && this.configLoaded) this.initialLoad(); 
    }

    connectedCallback() {
        if (this.recordId) this.init();
    }

    disconnectedCallback() { 
        this.stopPolling(); 
        if (this._observer) {
            this._observer.disconnect();
            this._observer = null;
        }
    }

    async init() {
        try {
            this.isLoading = true;
            
            // Fetch Config and Counts in parallel
            const [config, counts] = await Promise.all([
                getTimelineConfig(),
                getTimelineCounts({ caseId: this.recordId })
            ]);

            this.configId = config.configId;
            this.batchSize = config.batchSize || 10;
            this.pollingInterval = config.pollingInterval || 15000;
            this.debugMode = config.debugMode;
            this.showLoadTimeToast = config.showToast;
            
            // Map Counts
            this.totalEmailCount = counts.emailCount || 0;
            this.totalInternalCount = counts.internalCount || 0;
            this.totalPublicCount = counts.publicCount || 0;
            this.totalSystemCount = counts.systemCount || 0;

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
        }).catch(err => console.error(err));
    }

    // --- DATA LOADING ---
    initialLoad() {
        if (this.debugMode) console.log('initialLoad called - recordId:', this.recordId, 'configLoaded:', this.configLoaded);
        if (!this.recordId || !this.configLoaded) return;
        this.stopPolling();
        this.isLoading = true;
        this.allItems = [];
        this.allFiles = []; // Reset files cache
        if (this.debugMode) console.log('Cleared allItems, sortDirection:', this.sortDirection);
        this.hasMoreItems = true;
        this.error = undefined;
        this.isNewDataAvailable = false;
        this.lastRefreshDate = new Date().toISOString();
        const startTime = performance.now();
        this.fetchData(null, startTime).then(() => {
            // Only hide main spinner if we aren't waiting for files or if files are already done
            if (!this.showFiles || !this.isFilesLoading) {
                this.isLoading = false;
            }
            if (this.debugMode) console.log('Initial load complete, allItems count:', this.allItems.length);
            setTimeout(() => { this.renderedCallback(); this.startPolling(); }, 0);
        });

        if (this.showFiles) {
            this.fetchFiles(true).then(() => {
                this.isLoading = false; // Ensure main spinner hidden when files finish
            });
        }
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
        const lastId = lastItem ? lastItem.id : null;
        
        const startTime = performance.now(); // Start Timer

        this.isLoadingMore = true;
        this.fetchData(lastDate, startTime, lastId).then(() => { // Pass Timer and ID
            this.isLoadingMore = false;
            if(this.debugMode) console.log('Infinite load complete, total allItems count:', this.allItems.length);
            setTimeout(() => { this.renderedCallback(); }, 0);
        });
    }

    fetchData(referenceDate, startTime, lastSeenId) {
        return getTimelineData({ 
            caseId: this.recordId, 
            referenceDate: referenceDate,
            limitSize: this.batchSize,
            sortDirection: this.sortDirection,
            debugMode: this.debugMode,
            lastSeenId: lastSeenId
        })
        .then(data => {
            if(this.debugMode) console.log('Raw data received from Apex:', data ? data.length : 0, 'items');
            if (data && data.length > 0) {
                if(this.debugMode) console.log('First 3 items from Apex:');
                data.slice(0, 3).forEach((item, idx) => {
                    if(this.debugMode) console.log(`  [${idx}] ${item.createdDate} - ${item.title}`);
                });
            }
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
                if(this.debugMode) console.log('Processed items:', processed.length);
                this.allItems = [...this.allItems, ...processed];
                if(this.debugMode) console.log('Total allItems after adding:', this.allItems.length);
                if(this.debugMode) console.log('First 3 items in allItems:');
                this.allItems.slice(0, 3).forEach((item, idx) => {
                    if(this.debugMode) console.log(`  [${idx}] ${item.createdDate} - ${item.title}`);
                });
            } else {
                this.hasMoreItems = false;
            }
        }).catch(error => {
            this.error = error;
            this.isLoading = false;
            this.isLoadingMore = false;
            this.hasMoreItems = false;
        });
    }

    // --- PROCESS ITEM (The "Preview" Logic) ---
    processItem(item) {
        let processedItem = { ...item };

        // 1. Parse Email Content (Hybrid Split/DOM approach)
        if (processedItem.category === 'Email') {
            const serverHadHistory = processedItem.hasHistory;
            const parsed = this.parseEmailContent(processedItem.body);
            processedItem.body = parsed.newContent;
            
            // If the server already identified history, keep that flag true
            // even if the client-side parser doesn't find a new split point
            // in the already-stripped content.
            processedItem.hasHistory = serverHadHistory || parsed.hasHistory;
            
            // Only use the client-parsed history if it actually found something
            if (parsed.hasHistory) {
                processedItem.historyBody = parsed.historyContent;
            }
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

        const hasComments = processedItem.comments && processedItem.comments.length > 0;
        const commentCount = hasComments ? processedItem.comments.length : 0;
        const isInternal = processedItem.isInternal;
        const baseClass = 'slds-box slds-box_x-small';
        const internalClass = isInternal ? ' internal-note' : '';
        
        // Calculate initial box class based on default expansion
        let boxClass = isInternal 
            ? `${baseClass} slds-m-bottom_small${internalClass}`
            : `${baseClass} slds-m-bottom_small`;

        if (this.expandByDefault && hasComments) {
             boxClass = isInternal 
                ? `${baseClass} main-item-glued${internalClass}`
                : `${baseClass} main-item-glued`;
        }

        const commentBoxClass = isInternal
            ? `slds-box slds-box_x-small slds-m-bottom_small comment-container${internalClass}`
            : `slds-box slds-box_x-small slds-m-bottom_small comment-container`;

        return {
            ...processedItem,
            isExpanded: this.expandByDefault,
            historyExpanded: false, // Default history hidden
            previewText: previewText,
            previewStyle: lineClampStyle,
            rowStyle: '',
            boxClass: boxClass,
            commentBoxClass: commentBoxClass,
            hasComments: hasComments,
            commentCount: commentCount,
            emailBadgeClass: processedItem.isOutgoing 
                ? 'slds-badge outgoing-email-badge'
                : 'slds-badge slds-theme_success',
            isEmailCategory: processedItem.category === 'Email',
            isPublicCategory: processedItem.category === 'Public',
            isInternalCategory: processedItem.category === 'Internal',
            isSystemCategory: processedItem.category === 'System',
            isEmailMessage: (processedItem.id || '').startsWith('02s'), // EmailMessage Id prefix
            showEmailInfo: false, // Initialize email info popover as closed
            // Icons
            expandIcon: 'utility:chevronright'
        };
    }
    
    getBoxClass(item, isExpanded) {
        const baseClass = 'slds-box slds-box_x-small';
        const internalClass = item.isInternal ? ' internal-note' : '';
        
        // If expanded and has comments, remove bottom margin/radius to glue
        if (isExpanded && item.hasComments) {
            return `${baseClass} main-item-glued${internalClass}`;
        }
        return `${baseClass} slds-m-bottom_small${internalClass}`;
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

        // Reply headers are always near the start of the quoted block — cap to avoid
        // running [\s\S]{1,500} dot-all patterns on very large bodies.
        const searchWindow = cleaned.length > 20000 ? cleaned.substring(0, 20000) : cleaned;
        const htmlSplitIndex = this.findSplitIndex(searchWindow);
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
        // Fast-exit: if none of the anchor words that every reply header must contain are present,
        // skip all 13 regex patterns entirely.
        const anchors = ['wrote:', 'schreef', 'Original Message', 'Forwarded Message',
                         'Sent:', 'Skickat:', 'Envoy', 'Inviato', 'Enviado', 'écrit', '____'];
        if (!anchors.some(a => html.includes(a))) return -1;

        const patterns = [
            /On\s+[A-Za-z]{3}[\s\S]{0,200}?wrote:/i,
            /(?:Op|<b>Op<\/b>)\s+[\s\S]{0,100}?\s+(?:schreef|<b>schreef<\/b>)\s+[\s\S]{0,200}?:/i,
            /Op\s+[\s\S]{0,100}?\s+schreef\s+[\s\S]{0,200}?:/i,
            /-{3,}\s*(Original|Forwarded)\s+Message\s*-{3,}/i,
            /(?:From:|<b>From:<\/b>)[\s\S]{1,300}?(?:Sent:|<b>Sent:<\/b>)/i,
            /(?:Från:|<b>Från:<\/b>)[\s\S]{1,300}?(?:Skickat:|<b>Skickat:<\/b>)/i, // Swedish: Från/Skickat
            /From:.{1,100}?(&lt;|<).+?@.+?(&gt;|>)/i,
            /(?:De|<b>De)(?:[\s\S]{0,50}?):[\s\S]{1,500}?(?:Envoy|<b>Envoy)(?:[\s\S]{0,50}?):/i,
            /Da\s*:.{1,100}?Inviato\s*:/i, // Italian: Da: ... Inviato:
            /(?:De|<b>De)(?:[\s\S]{0,50}?):[\s\S]{1,250}?(?:Enviado|<b>Enviado)(?:[\s\S]{0,50}?):/i,
            /(?:De:|<b>De:<\/b>)[\s\S]{1,500}?(?:Enviado\s+el:|<b>Enviado\s+el:<\/b>)/i,
            /(?:Le|<b>Le)<\/b>?\s+[\s\S]{0,250}?(?:a\s+écrit|<b>a\s+écrit<\/b>)\s*:/i,
            /(?:De|<b>De)(?:[\s\S]{0,50}?):[\s\S]{1,500}?(?:en\s+nombre\s+de|<b>en\s+nombre\s+de)/i,
            /_{20,}\s*[\r\n]+\s*(?:From|De|On|Le|Op|<b>)/i
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
                    boxClass: this.getBoxClass(item, isNowExpanded),
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
            boxClass: this.getBoxClass(item, this.areAllExpanded),
            expandIcon: icon
        }));
        
        setTimeout(() => { this.renderedCallback(); }, 0);
    }

    async handleHistoryToggle(event) {
        event.preventDefault();
        const clickedId = event.currentTarget.dataset.id;
        
        const item = this.allItems.find(i => i.id === clickedId);
        if (item && !item.historyExpanded && !item.historyBody && item.hasHistory) {
            try {
                const history = await getEmailHistory({ emailId: clickedId });
                this.allItems = this.allItems.map(i => {
                    if (i.id === clickedId) {
                        return { ...i, historyBody: history, historyExpanded: true };
                    }
                    return i;
                });
            } catch (error) {
                console.error('Error fetching email history:', error);
            }
        } else {
            this.allItems = this.allItems.map(i => {
                if (i.id === clickedId) { return { ...i, historyExpanded: !i.historyExpanded }; }
                return i;
            });
        }
        
        setTimeout(() => { this.renderedCallback(); }, 0);
    }

    handleReplyAll(event) {
        event.preventDefault();
        event.stopPropagation();

        const emailMessageId = event.currentTarget.dataset.emailId;

        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: {
                apiName: 'EmailMessage._ReplyAll'
            },
            state: {
                recordId: emailMessageId
            }
        });

        // Fix email editor height after modal opens
        this.fixEmailEditorHeight();
    }

    fixEmailEditorHeight() {
        let attemptCount = 0;
        let appliedElements = [];
        
        const fixAttempt = () => {
            attemptCount++;
            
            const activeModal = document.querySelector('[role="dialog"].slds-modal.slds-fade-in-open');
            
            if (!activeModal) {
                return;
            }
            
            const aloha = activeModal.querySelector('.oneAlohaPage');
            const iframe = aloha?.querySelector('iframe');
            
            if (iframe && iframe.offsetHeight > 0) {
                const inQuickAction = !!activeModal.querySelector('.runtime_platform_actionsQuickActionWrapper');
                
                if (!inQuickAction) {
                    return;
                }
                
                const modalContainer = activeModal.querySelector('.slds-modal__container');
                const modalContent = activeModal.querySelector('.slds-modal__content');
                
                if (modalContainer) {
                    modalContainer.style.setProperty('height', '100vh', 'important');
                    modalContainer.style.setProperty('max-height', '100vh', 'important');
                    appliedElements.push({element: modalContainer, properties: ['height', 'max-height']});
                }
                
                if (modalContent) {
                    modalContent.style.setProperty('max-height', 'none', 'important');
                    modalContent.style.setProperty('overflow-y', 'visible', 'important');
                    appliedElements.push({element: modalContent, properties: ['max-height', 'overflow-y']});
                }
                
                const modalHeight = activeModal.offsetHeight;
                const alohaHeight = Math.floor(modalHeight * 0.50);
                aloha.style.setProperty('height', alohaHeight + 'px', 'important');
                iframe.style.setProperty('height', '100%', 'important');
                appliedElements.push({element: aloha, properties: ['height']});
                appliedElements.push({element: iframe, properties: ['height']});
                
                const forceAloha = aloha.querySelector('force-aloha-page');
                if (forceAloha) {
                    forceAloha.style.setProperty('height', '100%', 'important');
                    forceAloha.style.setProperty('display', 'block', 'important');
                    appliedElements.push({element: forceAloha, properties: ['height', 'display']});
                }
                
                try {
                    const iframeDoc = iframe.contentDocument || iframe.contentWindow.document;
                    const body = iframeDoc?.body;
                    
                    if (body) {
                        iframeDoc.documentElement.style.setProperty('height', '100%', 'important');
                        body.style.setProperty('height', '100%', 'important');
                        body.style.setProperty('margin', '0', 'important');
                        appliedElements.push({element: iframeDoc.documentElement, properties: ['height']});
                        appliedElements.push({element: body, properties: ['height', 'margin']});
                        
                        const ckeEditor = iframeDoc.querySelector('.cke_chrome');
                        const ckeContents = iframeDoc.querySelector('.cke_contents');
                        
                        if (ckeEditor && ckeContents) {
                            const iframeHeight = iframe.offsetHeight;
                            const editorHeight = Math.floor(iframeHeight * 0.95);
                            const contentsHeight = Math.floor(iframeHeight * 0.85);
                            
                            ckeEditor.style.setProperty('height', editorHeight + 'px', 'important');
                            ckeContents.style.setProperty('height', contentsHeight + 'px', 'important');
                            appliedElements.push({element: ckeEditor, properties: ['height']});
                            appliedElements.push({element: ckeContents, properties: ['height']});
                        }
                        
                        this.setupModalCloseCleanup(activeModal, appliedElements);
                    }
                } catch (e) {
                    console.warn('Could not access iframe content:', e.message);
                }
            } else if (attemptCount < 30) {
                setTimeout(fixAttempt, 300);
            }
        };
        
        setTimeout(fixAttempt, 2000);
    }

    setupModalCloseCleanup(modal, appliedElements) {
        const observer = new MutationObserver((mutations) => {
            if (!modal.classList.contains('slds-fade-in-open')) {
                appliedElements.forEach(({element, properties}) => {
                    properties.forEach(prop => {
                        if (element && element.style) {
                            element.style.removeProperty(prop);
                        }
                    });
                });
                observer.disconnect();
            }
        });
        
        observer.observe(modal, {
            attributes: true,
            attributeFilter: ['class']
        });
    }

    renderedCallback() {
        if (this.debugMode) console.log('Timeline renderedCallback starting...');

        if (this.filteredData && this.filteredData.length > 0) {
            this.filteredData.forEach(item => {
                try {
                    // 1. EXPANDED VIEW
                    if (item.isExpanded) {
                        const bodyContainer = this.template.querySelector(`[data-body-id="${item.id}"]`);
                        if (bodyContainer && item.body && bodyContainer.dataset.rendered !== 'true') {
                            bodyContainer.innerHTML = item.body;
                            bodyContainer.dataset.rendered = 'true';
                        } else if (!bodyContainer && this.debugMode) {
                            console.warn('Could not find bodyContainer for expanded item:', item.id);
                        }
                        
                        // Recipient HTML
                        if (item.isEmailCategory) {
                            ['to', 'cc', 'bcc'].forEach(type => {
                                const container = this.template.querySelector(`[data-expanded-${type}="${item.id}"]`);
                                if (container && item[`email${type.charAt(0).toUpperCase() + type.slice(1)}`] && container.dataset.rendered !== 'true') {
                                    container.innerHTML = item[`email${type.charAt(0).toUpperCase() + type.slice(1)}`];
                                    container.dataset.rendered = 'true';
                                }
                            });
                        }
                        
                        if (item.historyExpanded && item.historyBody) {
                            const historyContainer = this.template.querySelector(`[data-history-id="${item.id}"]`);
                            if (historyContainer && historyContainer.dataset.rendered !== 'true') {
                                historyContainer.innerHTML = item.historyBody;
                                historyContainer.dataset.rendered = 'true';
                            }
                        }
                        const attachContainer = this.template.querySelector(`[data-attachments-id="${item.id}"]`);
                        if (attachContainer && item.attachmentsHtml && attachContainer.dataset.rendered !== 'true') {
                            attachContainer.innerHTML = item.attachmentsHtml;
                            attachContainer.dataset.rendered = 'true';
                        }
                    } 
                    
                    // 2. COLLAPSED VIEW
                    else if (this.showAttachmentsCollapsed) {
                        const collapsedAttachContainer = this.template.querySelector(`[data-attachments-collapsed-id="${item.id}"]`);
                        if (collapsedAttachContainer && item.attachmentsHtml && collapsedAttachContainer.dataset.rendered !== 'true') {
                            collapsedAttachContainer.innerHTML = item.attachmentsHtml;
                            collapsedAttachContainer.dataset.rendered = 'true';
                            collapsedAttachContainer.addEventListener('click', (e) => e.stopPropagation());
                        }
                    }
                    
                    // 3. POPOVER
                    if (item.showEmailInfo && item.isEmailCategory) {
                        ['to', 'cc', 'bcc', 'from'].forEach(type => {
                            const container = this.template.querySelector(`[data-popover-${type}="${item.id}"]`);
                            if (container && item[`email${type.charAt(0).toUpperCase() + type.slice(1)}`] && container.dataset.rendered !== 'true') {
                                container.innerHTML = item[`email${type.charAt(0).toUpperCase() + type.slice(1)}`];
                                container.dataset.rendered = 'true';
                            }
                        });
                    }
                } catch (e) {
                    if (this.debugMode) console.error('Error in renderedCallback loop for item ' + item.id, e);
                }
            });
        }
        
        this.setupInfiniteScroll();
    }

    setupInfiniteScroll() {
        if (this._observer) {
            this._observer.disconnect();
        }

        const sentinel = this.template.querySelector('.infinite-scroll-sentinel');
        if (sentinel) {
            this._observer = new IntersectionObserver((entries) => {
                if (entries[0].isIntersecting && this.hasMoreItems && !this.isLoadingMore && !this.isLoading) {
                    this.handleLoadMore();
                }
            }, { threshold: 0.1 });
            this._observer.observe(sentinel);
        }
    }

    /**
     * UNIVERSAL EVENT DELEGATION
     * Handles clicks on any dynamically injected HTML (Emails, Comments, Mentions)
     */
    handleGlobalClick(event) {
        const target = event.target;
        console.log('CaseTimeline: GlobalClick triggered by', target.tagName, 'Class:', target.className);
        
        // 1. Image Preview Links
        const previewLink = target.closest('.image-preview-link');
        if (previewLink) {
            console.log('CaseTimeline: Intercepted attachment click. ID:', previewLink.dataset.docId);
            event.preventDefault();
            event.stopPropagation();
            if (previewLink.dataset.docId) {
                this.handleImagePreviewClick(previewLink.dataset.docId);
            } else {
                console.warn('CaseTimeline: Clicked preview link but data-doc-id is missing.');
            }
            return;
        }

        // 2. Copy Code Buttons
        const copyBtn = target.closest('.copy-btn');
        if (copyBtn) {
            event.preventDefault();
            event.stopPropagation();
            this.handleCopyCode(copyBtn);
            return;
        }

        // 3. Mention Links
        const mentionLink = target.closest('.mention-link');
        if (mentionLink) {
            event.preventDefault();
            event.stopPropagation();
            this.handleMentionClick(mentionLink.dataset.recordId);
            return;
        }

        // 4. Email Recipient Links
        const recipientLink = target.closest('.email-recipient-link');
        if (recipientLink) {
            event.preventDefault();
            event.stopPropagation();
            this.handleRecipientClick(recipientLink.dataset.recordId);
            return;
        }
    }

    handleImagePreviewClick(docId) {
        if (!docId) return;

        if (docId.startsWith('00P')) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: docId, objectApiName: 'Attachment', actionName: 'view' }
            });
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: { pageName: 'filePreview' },
                state: { selectedRecordId: docId }
            });
        }
    }

    handleCopyCode(btn) {
        const wrapper = btn.closest('.code-wrapper');
        const hiddenTextarea = wrapper.querySelector('.raw-code-storage');
        const cleanCode = hiddenTextarea ? hiddenTextarea.value : '';

        navigator.clipboard.writeText(cleanCode).then(() => {
            const originalText = btn.textContent;
            btn.textContent = 'Copied!';
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => { btn.textContent = originalText; }, 2000);
        });
    }

    handleMentionClick(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: recordId, actionName: 'view' }
        });
    }

    handleRecipientClick(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: recordId, actionName: 'view' }
        });
    }

    // GETTERS
    get sortIcon() { return this.sortDirection === 'desc' ? 'utility:arrowdown' : 'utility:arrowup'; }
    get sortLabel() { return this.sortDirection === 'desc' ? 'Newest First' : 'Oldest First'; }
    get expandCollapseLabel() { return this.areAllExpanded ? 'Collapse All' : 'Expand All'; }
    get expandCollapseIcon() { return this.areAllExpanded ? 'utility:collapse_all' : 'utility:expand_all'; }
    
    get hasData() { return this.filteredData && this.filteredData.length > 0; }
    get emailLabel() { return `Emails (${this.totalEmailCount})`; }
    get publicLabel() { return `Public (${this.totalPublicCount})`; }
    get internalLabel() { return `Internal (${this.totalInternalCount})`; }
    get systemLabel() { return `System (${this.totalSystemCount})`; }

    get filesButtonLabel() {
        return this.showFiles ? 'Show Timeline' : 'List files';
    }

    get filesButtonVariant() {
        return this.showFiles ? 'brand' : 'neutral';
    }

    fetchFiles(isInitial = false) {
        if (isInitial) {
            this.fileOffset = 0;
            this.allFiles = [];
            // Do not reset hasMoreFiles to true here to prevent button flicker
            this.isFilesLoading = true;
        } else {
            this.isFilesLoadingMore = true;
        }

        const sortByField = this.fileSortBy === 'formattedSize' ? 'size' : this.fileSortBy;

        return getFiles({ 
            caseId: this.recordId, 
            limitCount: this.fileLimit, 
            offset: this.fileOffset,
            searchTerm: this.fileSearchKey,
            sortBy: sortByField,
            sortDir: this.fileSortDirection,
            hideDuplicates: this.showUniqueFiles
        })
        .then(data => {
            // Bug 2 Fix: Detect next page using extra record
            if (data.length > this.fileLimit) {
                this.hasMoreFiles = true;
                data.pop(); // Remove the +1 record
            } else {
                this.hasMoreFiles = false;
            }

            const formattedData = data.map(f => ({
                ...f,
                formattedSize: this.formatSize(f.size)
            }));

            // Bug 1 Fix: Use a Map to ensure unique IDs in the local list
            const currentFilesMap = new Map(this.allFiles.map(f => [f.id, f]));
            formattedData.forEach(f => currentFilesMap.set(f.id, f));
            this.allFiles = Array.from(currentFilesMap.values());

            this.isFilesInitialized = true; // Bug 1: Initialization done
            this.isFilesLoading = false;
            this.isFilesLoadingMore = false;
            this.isLoading = false; 
            
            // Restore focus after refresh (Ensure search box stays focused while typing)
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                const input = this.template.querySelector('[data-id="file-search-input"]');
                if (input) input.focus();
            }, 0);
        })
        .catch(error => {
            console.error('Error fetching files:', error);
            this.isFilesLoading = false;
            this.isFilesLoadingMore = false;
        });
    }

    handleFilesToggle() {
        this.showFiles = !this.showFiles;
        if (this.showFiles && this.allFiles.length === 0) {
            this.fetchFiles(true);
        }
    }

    handleFileSearchChange(event) {
        this.draftFileSearchKey = event.target.value;
        if (!this.isManualSearch) {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            if (this._searchTimer) clearTimeout(this._searchTimer);
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._searchTimer = setTimeout(() => {
                this.fileSearchKey = this.draftFileSearchKey;
                this.fetchFiles(true);
            }, 1000);
        }
    }

    handleFileSearchKeyUp(event) {
        if (event.keyCode === 13) {
            this.handleFileSearchClick();
        }
    }

    handleFileSearchClick() {
        if (this._searchTimer) clearTimeout(this._searchTimer);
        this.fileSearchKey = this.draftFileSearchKey;
        this.fetchFiles(true);
    }

    handleUniqueToggle(event) {
        this.showUniqueFiles = event.target.checked;
        this.fetchFiles(true);
    }

    handleFileSort(event) {
        this.fileSortBy = event.detail.fieldName;
        this.fileSortDirection = event.detail.sortDirection;
        this.fetchFiles(true);
    }

    handleFilesLoadMore(event) {
        if (!this.hasMoreFiles || this.isFilesLoadingMore) return;
        this.fileOffset += this.fileLimit;
        this.fetchFiles(false);
    }

    handleFileRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'open_file') {
            this.handleImagePreviewClick(row.id);
        }
    }

    formatSize(bytes) {
        if (!bytes || bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

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
        if(this.debugMode) console.log('Sort toggled from', oldDirection, 'to', this.sortDirection);
        // Reload data to get items in the new sort order
        this.initialLoad();
    }

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

    handleAddCommentChange(event) {
        const itemId = event.target.dataset.id;
        const value = event.target.value;
        this.allItems = this.allItems.map(item => {
            if (item.id === itemId) {
                return { ...item, draftComment: value };
            }
            return item;
        });
    }

    handlePostComment(event) {
        const itemId = event.target.dataset.id;
        const item = this.allItems.find(i => i.id === itemId);
        
        if (!item || !item.draftComment || !item.draftComment.trim()) return;
        
        // If feedItemId is missing (e.g. for an email that has no mapped feed item yet), we can't post
        if (!item.feedItemId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Cannot post comment: No associated Feed Item found.',
                    variant: 'error'
                })
            );
            return;
        }

        addComment({ feedItemId: item.feedItemId, commentBody: item.draftComment })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Comment posted',
                        variant: 'success'
                    })
                );
                // Clear draft and refresh
                this.allItems = this.allItems.map(i => {
                    if (i.id === itemId) {
                        return { ...i, draftComment: '' }; // Clear input
                    }
                    return i;
                });
                this.handleRefresh(); // Refresh to show new comment
            })
            .catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error posting comment',
                        message: error.body ? error.body.message : error.message,
                        variant: 'error'
                    })
                );
            });
    }
}