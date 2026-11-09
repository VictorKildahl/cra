// Dashlane's device check (GitHub #292): open a page with tabs.create, wait for the returned
// tab to finish loading, then talk to that tab by its id. In Chrome and Arc the returned id is
// the tab that loads the page. The toolbar button runs it, and the answer opens as a tab of its
// own: <page>?n=answer-loaded-<bool>-get-<found|missing>-created-<n>, n being how many tabs
// tabs.onCreated announced for the one tabs.create (Chrome: 1).
chrome.action.onClicked.addListener(async (tab) => {
  const origin = new URL(tab.url).origin;
  let created = 0;
  const count = () => { created += 1; };
  chrome.tabs.onCreated.addListener(count);
  const opened = await chrome.tabs.create({ url: origin + '/page.html?n=opened' });
  const loaded = await new Promise((resolve) => {
    const timer = setTimeout(() => resolve(false), 5000);
    const done = (id, info) => {
      if (id !== opened.id || info.status !== 'complete') return;
      clearTimeout(timer);
      chrome.tabs.onUpdated.removeListener(done);
      resolve(true);
    };
    chrome.tabs.onUpdated.addListener(done);
  });
  chrome.tabs.onCreated.removeListener(count);
  const found = await chrome.tabs.get(opened.id).then(() => 'found', () => 'missing');
  await chrome.tabs.create({ url: `${origin}/page.html?n=answer-loaded-${loaded}-get-${found}-created-${created}` });
});
