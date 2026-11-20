// An extension popup's Settings button (GitHub #626 Obsidian Web Clipper and Keeper, #631 LeechBlock NG):
// the options page opens as a tab while the popup is still up, and Chromium closes the popup as the tab
// goes in. "worker" asks the service worker to chrome.tabs.create it, "runtime" calls
// chrome.runtime.openOptionsPage() from the popup itself (worker.js keeps which, and the page's origin).
chrome.storage.session.get('settings').then(async ({ settings }) => {
  await fetch(`${settings.origin}/page.html?n=settings-shown-${settings.how}`, { mode: 'no-cors' });
  if (settings.how === 'runtime') chrome.runtime.openOptionsPage();
  else chrome.runtime.sendMessage('open-options-tab').catch(console.error);
});
