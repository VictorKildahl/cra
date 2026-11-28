// Installed in Cra's isolated world. Never choose a consent option or record consent.
(cookieBanners, warnings, bannerSelector) => {
    window.__craPageRecovery?.();
    if (!cookieBanners && !warnings) return;

    const hidden = new Set();
    const overlays = new Set();
    const candidates = new Set();
    const candidateObserver = new MutationObserver(() => {
        for (const element of candidates) queue(element);
    });
    function trackCandidate(element) {
        if (candidates.has(element)) return;
        candidates.add(element);
        // Some walls insert the text while hidden and only later style a parent as an overlay.
        for (let parent = element; parent && parent !== document.body; parent = parent.parentElement)
            candidateObserver.observe(parent, {attributes:true, attributeFilter:['class','style','hidden']});
    }
    const sheet = new CSSStyleSheet();
    const mark = 'data-cra-hidden-blocker-notice';
    const unlock = 'data-cra-blocker-scroll';
    sheet.replaceSync(`[${mark}]{display:none!important}
        html[${unlock}]{overflow-y:auto!important}
        html[${unlock}] > body[style*="overflow"]{overflow-y:visible!important}`);
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];

    const warning = /(?:disable|disabling|turn off) (?:my |your |the )?ad[ -]?blocker|using an ad[ -]?blocker|your browser or blocker is impacting your experience/i;
    const unrelated = /cookie preferences|sign in to continue|subscribe to (?:read|continue)|enter your password/i;
    function hide(node, overlay) {
        if (hidden.has(node)) return;
        hidden.add(node);
        node.setAttribute(mark, '');
        if (overlay) overlays.add(node);
        if (node.matches('dialog:modal')) node.close();
    }
    function checkNotice(element) {
        if (!warnings || !element.isConnected || element.closest('article,pre,code,form,[contenteditable=true]')) return;
        const text = element.textContent.trim();
        if (text.length > 420 || !warning.test(text)) return;
        trackCandidate(element);
        if (!element.getClientRects().length) return;
        let section;
        for (let node = element; node && node !== document.body; node = node.parentElement) {
            if (node.matches('main,article,nav,header,footer') || node.textContent.length > 2200 || unrelated.test(node.innerText)) break;
            if (node.matches('section')) section = node;
            if (node.matches('dialog:modal') || getComputedStyle(node).position === 'fixed') {
                if (node.querySelector('article,form,input,textarea,video,nav')) break;
                hide(node, true);
                return;
            }
        }
        // A compact ad-blocker card can sit inside an otherwise functional sidebar.
        if (section && warning.test(section.querySelector('h2,h3')?.innerText || '')
            && section.innerText.length <= 600 && !section.querySelector('form,article,nav')
            && [...section.querySelectorAll('li,button,a')].some(item => warning.test(item.innerText))) hide(section, false);
        else if (/^disable your ad blocker to view promotions[.!]?$/i.test(text)) hide(element, false);
    }
    function inspect(root) {
        if (root.nodeType !== Node.ELEMENT_NODE || !root.isConnected || root.closest('script,style,template')) return;
        if (cookieBanners) {
            // A CSS-hidden top-layer dialog still makes the rest of the document inert.
            const selector = 'dialog:modal';
            const dialogs = root.matches(selector) ? [root] : root.querySelectorAll(selector);
            for (const dialog of dialogs) {
                if (dialog.matches(bannerSelector + ',[id*="cookie" i],[id*="consent" i]') && getComputedStyle(dialog).display === 'none') dialog.close();
            }
        }
        if (!warnings) return;
        // Inline markup can split the instruction across several text nodes.
        const modalSelector = 'dialog:modal,[role="dialog"][aria-modal="true"]';
        const parentModal = root.closest(modalSelector);
        const modals = parentModal ? [parentModal] : root.querySelectorAll(modalSelector);
        for (const modal of modals) {
            if (modal.getClientRects().length && modal.textContent.length <= 2200
                && !modal.querySelector('article,form,input,textarea,video,nav,[contenteditable=true]')) {
                const text = modal.innerText.replace(/\s+/g, ' ');
                if (warning.test(text) && !unrelated.test(text)) hide(modal, true);
            }
        }
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        for (let text = walker.nextNode(); text; text = walker.nextNode()) {
            if (text.length <= 420 && warning.test(text.data) && !text.parentElement?.matches('script,style,noscript'))
                checkNotice(text.parentElement);
        }
    }
    let timer;
    const pending = new Set();
    const changedNotices = new Set();
    function flush() {
        timer = undefined;
        // Sites may recycle an overlay for a login, preference pane or article.
        // Re-evaluate its current contents without our own display override.
        for (const node of hidden) {
            if (node.isConnected && !changedNotices.has(node)) continue;
            node.removeAttribute(mark);
            hidden.delete(node);
            overlays.delete(node);
            if (node.isConnected) pending.add(node);
        }
        changedNotices.clear();
        for (const node of pending) {
            if (node.parentElement && pending.has(node.parentElement)) continue;
            if (!node.parentElement?.closest('[' + mark + ']')) inspect(node);
        }
        pending.clear();
        for (const element of candidates) {
            if (!element.isConnected || element.closest('[' + mark + ']')) candidates.delete(element);
        }
        if (!candidates.size) candidateObserver.disconnect();
        const consent = cookieBanners && document.querySelector('#iubenda-cs-banner.iubenda-cs-visible');
        const hiddenConsent = consent && getComputedStyle(consent).display === 'none';
        if (!overlays.size && !hiddenConsent) {
            document.documentElement.removeAttribute(unlock);
            return;
        }
        const otherDialog = [...document.querySelectorAll('dialog:modal,[aria-modal="true"]')]
            .some(node => node.getClientRects().length && !node.closest('[' + mark + ']'));
        // Only release explicit inline locks belonging to an observed blocker overlay.
        const locked = [document.documentElement, document.body].some(node => node?.style.overflowY === 'hidden');
        document.documentElement.toggleAttribute(unlock, locked && !otherDialog);
    }
    function queue(node) {
        if (!node || pending.has(node)) return;
        pending.add(node);
        if (timer === undefined) timer = setTimeout(flush, 80);
    }
    // Consent managers can lock the root after mounting and hiding their banner.
    // Watch only the two scroll roots for inline style changes.
    const lockObserver = new MutationObserver(() => {
        for (const element of candidates) queue(element);
        if (timer === undefined) timer = setTimeout(flush, 80);
    });
    function observeScrollRoots() {
        if (document.documentElement) lockObserver.observe(document.documentElement, {attributes:true, attributeFilter:['style']});
        if (document.body) lockObserver.observe(document.body, {attributes:true, attributeFilter:['style']});
    }
    observeScrollRoots();
    const onReady = () => { observeScrollRoots(); queue(document.documentElement); };
    document.addEventListener('DOMContentLoaded', onReady, {once:true});
    window.addEventListener('load', onReady, {once:true});
    const observer = new MutationObserver(entries => {
        for (const entry of entries) {
            const target = entry.target.nodeType === Node.ELEMENT_NODE ? entry.target : entry.target.parentElement;
            const notice = hidden.size && target?.closest('[' + mark + ']');
            if (notice && (entry.type !== 'attributes' || (entry.attributeName === 'open' && notice.matches(':modal')))) {
                changedNotices.add(notice);
                queue(notice);
            }
            if (entry.type === 'attributes') {
                if (entry.attributeName !== 'class' || entry.target.id === 'iubenda-cs-banner' || (cookieBanners && target.matches('dialog:modal'))) queue(entry.target);
            }
            else if (entry.type === 'characterData') {
                if (warning.test(entry.target.data)) queue(entry.target.parentElement);
            }
            else {
                // A removed node may already have been reused and reattached by
                // the time MutationObserver delivers both changes.
                for (const removed of entry.removedNodes) {
                    for (const node of hidden) if (removed.contains(node)) changedNotices.add(node);
                }
                for (const node of entry.addedNodes) {
                    if (node.nodeType === Node.ELEMENT_NODE) queue(node);
                    else if (warnings && node.nodeType === Node.TEXT_NODE && warning.test(node.data)) queue(node.parentElement);
                }
                if (entry.removedNodes.length && (hidden.size || document.documentElement.hasAttribute(unlock)) && timer === undefined)
                    timer = setTimeout(flush, 80);
            }
        }
    });
    observer.observe(document, {subtree:true, childList:true, characterData:warnings, attributes:true, attributeFilter:cookieBanners ? ['open','aria-modal','class'] : ['open','aria-modal']});
    queue(document.documentElement);
    window.__craPageRecovery = () => {
        observer.disconnect();
        lockObserver.disconnect();
        candidateObserver.disconnect();
        document.removeEventListener('DOMContentLoaded', onReady);
        window.removeEventListener('load', onReady);
        clearTimeout(timer);
        for (const node of hidden) node.removeAttribute(mark);
        document.documentElement.removeAttribute(unlock);
        document.adoptedStyleSheets = document.adoptedStyleSheets.filter(s => s !== sheet);
        delete window.__craPageRecovery;
    };
}
