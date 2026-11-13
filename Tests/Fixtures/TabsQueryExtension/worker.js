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
