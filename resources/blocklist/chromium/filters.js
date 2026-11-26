// Chromium loads this code from the signed app. The native host sends only
// the selected rule snapshot and never receives browsing URLs.
let port;
let updates = Promise.resolve();

// Install the recovery handler only for selections that block this SDK across sites.
// Exact host exclusions mirror the top-level pause for the network filters.
const loaderID = 'adshield-load-error';
function loaderSettings(snapshot) {
    const pauses = new Set((snapshot.siteExceptions || []).flatMap(rule => rule.condition.requestDomains || []));
    const excludeMatches = new Set(Array.from(pauses, host => `*://${host}/*`));
    let blocksLoader = false;
    // Outside these domain subtrees an exception allows the loader.
    let remainingHosts;
    const within = (host, root) => host === root || host.endsWith('.' + root);
    for (const { action, condition } of snapshot.rules) {
        if (action.type === 'allowAllRequests') {
            // Frame exceptions apply to their descendant requests too. A document
            // pattern without a bounded host cannot safely scope a registration.
            if (!condition.requestDomains?.length) return null;
            for (const host of condition.requestDomains) excludeMatches.add(`*://*.${host}/*`);
            continue;
        }
        if (condition.domainType === 'firstParty'
            || (condition.resourceTypes && !condition.resourceTypes.includes('script'))
            || condition.excludedResourceTypes?.includes('script')) continue;
        const domainRule = condition.requestDomains?.includes('html-load.com');
        if (action.type === 'allow' && (domainRule || condition.urlFilter?.startsWith('||html-load.com/'))) {
            // Respect an explicit loader exception even if it only allows some SDK paths.
            if (!condition.initiatorDomains?.length) {
                const roots = condition.excludedInitiatorDomains || [];
                if (!roots.length) return null;
                if (!remainingHosts) remainingHosts = roots;
                else {
                    const intersection = new Set();
                    for (const a of remainingHosts) for (const b of roots) {
                        if (within(a, b)) intersection.add(a);
                        else if (within(b, a)) intersection.add(b);
                    }
                    remainingHosts = [...intersection];
                }
                continue;
            }
            for (const host of condition.initiatorDomains) excludeMatches.add(`*://*.${host}/*`);
        }
        if (action.type === 'block' && domainRule && !condition.urlFilter
            && !condition.initiatorDomains && !condition.excludedInitiatorDomains) blocksLoader = true;
    }
    if (!blocksLoader || remainingHosts?.length === 0) return null;
    return {
        id: loaderID, matches: remainingHosts ? remainingHosts.map(host => `*://*.${host}/*`).sort() : ['http://*/*', 'https://*/*'], excludeMatches: [...excludeMatches].sort(),
        js: ['adshield.js'], runAt: 'document_start',
    };
}

async function setLoader(previous, next) {
    const scripting = chrome.scripting;
    if (previous && !next) await scripting.unregisterContentScripts({ ids: [loaderID] });
    else if (!previous && next) await scripting.registerContentScripts([next]);
    else if (previous && next) {
        const oldHosts = [...(previous.excludeMatches || [])].sort();
        if (JSON.stringify(oldHosts) !== JSON.stringify(next.excludeMatches || [])
            || JSON.stringify([...(previous.matches || [])].sort()) !== JSON.stringify([...next.matches].sort())) {
            await scripting.updateContentScripts([{ id: loaderID, matches: next.matches, excludeMatches: next.excludeMatches || [] }]);
        }
    }
}

function replacement(old, next) {
    return { removeRuleIds: old.map(rule => rule.id), addRules: next };
}

async function applySnapshot(snapshot) {
    const { revision, rules, siteExceptions = [] } = snapshot;
    const storage = chrome.storage.session;
    if ((await storage.get('appliedFilterRevision')).appliedFilterRevision === revision) return;
    const dnr = chrome.declarativeNetRequest;
    const [dynamic, session, registered] = await Promise.all([
        dnr.getDynamicRules(), dnr.getSessionRules(),
        chrome.scripting.getRegisteredContentScripts({ ids: [loaderID] }),
    ]);
    const loader = loaderSettings(snapshot);
    // Invalidate before changing anything. After an interrupted service worker
    // the next connection reconciles all three parts against Chromium itself.
    await storage.remove('appliedFilterRevision');
    await setLoader(registered[0], loader);
    let changedSession = false;
    try {
        if (session.length || siteExceptions.length) {
            await dnr.updateSessionRules(replacement(session, siteExceptions));
            changedSession = true;
        }
        // Chromium applies each DNR update atomically. Commit persistent rules last.
        await dnr.updateDynamicRules(replacement(dynamic, rules));
    } catch (error) {
        try {
            if (changedSession) await dnr.updateSessionRules(replacement(siteExceptions, session));
        } finally {
            await setLoader(loader, registered[0]);
        }
        throw error;
    }
    // A cache write failure only means the next connection will reconcile again.
    try { await storage.set({ appliedFilterRevision: revision }); }
    catch (error) { console.warn('Cra filter revision cache:', error.message); }
}

function connect() {
    if (port) return;
    const connection = chrome.runtime.connectNative('dk.kildahl.cra.filters');
    port = connection;
    let revision;
    let decoder;
    let parts;

    function enqueue(id, task) {
        const current = () => port === connection && revision === id;
        updates = updates.then(async () => {
            if (current()) await task(current);
        }).catch(error => {
            console.error('Cra network filters:', error.message);
            if (current()) connection.postMessage({ failed: id });
        });
    }

    connection.onMessage.addListener(message => {
        if (message.revision) {
            revision = message.revision;
            decoder = new TextDecoder();
            parts = [];
        } else if (message.id === revision && parts) {
            if (message.chunk) {
                const bytes = Uint8Array.from(atob(message.chunk), ch => ch.charCodeAt(0));
                parts.push(decoder.decode(bytes, { stream: true }));
            } else if (message.done) {
                parts.push(decoder.decode());
                const json = parts.join('');
                const id = revision;
                parts = undefined;
                enqueue(id, async current => {
                    const snapshot = JSON.parse(json);
                    if (snapshot.revision !== id) throw new Error('Unexpected filter revision');
                    await applySnapshot(snapshot);
                    if (current()) connection.postMessage({ applied: id });
                });
            } else if (message.error) {
                parts = undefined;
                connection.postMessage({ failed: revision });
            }
        }
    });
    connection.onDisconnect.addListener(() => {
        void chrome.runtime.lastError;
        if (port === connection) port = undefined;
        chrome.alarms.create('reconnect', { delayInMinutes: 0.5 });
    });
}
chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
chrome.alarms.onAlarm.addListener(connect);
connect();
