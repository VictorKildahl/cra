// Chromium loads this code from the signed app. The native host sends only
// the selected rule snapshot and never receives browsing URLs.
let port;
let updates = Promise.resolve();

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
                    if (snapshot.revision !== id) return;
                    const stored = await chrome.storage.local.get('revision');
                    if (stored.revision === id) {
                        if (current()) connection.postMessage({ applied: id });
                        return;
                    }
                    const old = await chrome.declarativeNetRequest.getDynamicRules();
                    if (!current()) return;
                    await chrome.declarativeNetRequest.updateDynamicRules({
                        removeRuleIds: old.map(rule => rule.id), addRules: snapshot.rules
                    });
                    await chrome.storage.local.set({ revision: id });
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
