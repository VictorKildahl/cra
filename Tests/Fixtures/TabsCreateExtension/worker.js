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

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (!sender.tab) return;
  let action;
  if (message === 'popup-window') {
    action = chrome.windows.create({ url: chrome.runtime.getURL('popup.html'), type: 'popup', width: 400, height: 300 });
  } else if (message === 'popup-fullscreen') {
    action = chrome.windows.getAll({ windowTypes: ['popup'] }).then((windows) =>
      Promise.all(windows.map((window) => chrome.windows.update(window.id, { state: 'fullscreen' }))));
  } else if (message === 'badge') {
    // GitHub #106: what an extension sets on its toolbar action reaches Cra's button.
    action = Promise.all([chrome.action.setBadgeText({ text: '7' }), chrome.action.setTitle({ title: 'Seven' })]);
  } else if (message === 'close-popup') {
    action = chrome.windows.getAll({ windowTypes: ['popup'] }).then((windows) =>
      Promise.all(windows.map((window) => chrome.windows.remove(window.id))));
  } else {
    return;
  }
  action.then(() => reply(true), (error) => { console.error(error); reply(false); });
  return true;
});
