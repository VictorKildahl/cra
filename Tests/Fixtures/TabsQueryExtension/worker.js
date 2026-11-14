// Cra's spare page (SparePages): made ahead for the next tab, with no address, and hidden from
// extensions until a tab takes it. The toolbar button opens
// <page>?n=tabs-<n>-blank-<n>-windows-<n>: every tab chrome.tabs.query reports, those of them with
// no address (url and pendingUrl empty or about:blank), and every window chrome.windows.getAll does.
chrome.action.onClicked.addListener(async (tab) => {
  const origin = new URL(tab.url).origin;
  const tabs = await chrome.tabs.query({});
  const blank = tabs.filter((t) => !(t.url || t.pendingUrl) || (t.url || t.pendingUrl) === 'about:blank').length;
  const windows = await chrome.windows.getAll({});
  await chrome.tabs.create({ url: `${origin}/page.html?n=tabs-${tabs.length}-blank-${blank}-windows-${windows.length}` });
});

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (message?.type !== 'context' || !sender.tab) return;
  (async () => {
    if (message.label === 'background') {
      await chrome.tabs.create({ url: `${new URL(sender.tab.url).origin}/extension-context.html?n=unselected`, active: false });
    }
    const byId = await chrome.tabs.query({ active: true, windowId: chrome.windows.WINDOW_ID_CURRENT });
    const current = await chrome.tabs.query({ active: true, currentWindow: true });
    const last = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
    const window = await chrome.windows.get(sender.tab.windowId);
    const page = new URL(sender.tab.url).searchParams.get('n');
    const active = byId[0]?.url ? new URL(byId[0].url).searchParams.get('n') : 'missing';
    return `${message.label} current=${byId[0]?.id === sender.tab.id} currentWindow=${current[0]?.id === sender.tab.id} last=${last[0]?.id === sender.tab.id} type=${window.type} page=${page} active=${active}`;
  })().then(reply, (error) => reply(`error: ${error.message}`));
  return true;
});
