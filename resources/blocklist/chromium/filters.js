// Chromium loads this code from the signed app. The native host sends only
// the selected rule snapshot and never receives browsing URLs.
let port;
let updates = Promise.resolve();

function replacement(old, next) {
    return { removeRuleIds: old.map(rule => rule.id), addRules: next };
}

async function applySnapshot(snapshot) {
    const { revision, rules, siteExceptions = [] } = snapshot;
    const storage = chrome.storage.session;
    if ((await storage.get('appliedFilterRevision')).appliedFilterRevision === revision) return;
    const dnr = chrome.declarativeNetRequest;
    const [dynamic, session] = await Promise.all([
        dnr.getDynamicRules(), dnr.getSessionRules(),
    ]);
    // Invalidate before changing anything. After an interrupted service worker
    // the next connection reconciles both rule sets against Chromium itself.
    await storage.remove('appliedFilterRevision');
    let changedSession = false;
    try {
        if (session.length || siteExceptions.length) {
            await dnr.updateSessionRules(replacement(session, siteExceptions));
            changedSession = true;
        }
        // Chromium applies each DNR update atomically. Commit persistent rules last.
        await dnr.updateDynamicRules(replacement(dynamic, rules));
    } catch (error) {
        if (changedSession) await dnr.updateSessionRules(replacement(siteExceptions, session));
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
