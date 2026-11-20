// An extension popup's Settings button (GitHub #626 Obsidian Web Clipper and Keeper, #631 LeechBlock NG):
// the options page opens as a tab while the popup is still up, and Chromium closes the popup as the tab
// goes in. "worker" asks the service worker to chrome.tabs.create it, "runtime" calls
// chrome.runtime.openOptionsPage() from the popup itself (worker.js keeps which, and the page's origin).
// "close" is a Tampermonkey button that opens nothing (#653): the worker answers, the popup closes itself.
chrome.storage.session.get('settings').then(async ({ settings }) => {
  await fetch(`${settings.origin}/page.html?n=settings-shown-${settings.how}`, { mode: 'no-cors' });
  if (settings.how === 'runtime') chrome.runtime.openOptionsPage();
  else if (settings.how === 'close') {
    // Clicked a moment after the popup came up, once Cra has framed it and it has the keys.
    await new Promise((resolve) => setTimeout(resolve, 1500));
    await fetch(`${settings.origin}/page.html?n=settings-press-close`, { mode: 'no-cors' });
    chrome.runtime.sendMessage('button-press').then(() => window.close(), console.error);
  }
  // Tampermonkey's Dashboard (#634) closes its popup itself once the worker answers, if Chromium hasn't yet.
  else chrome.runtime.sendMessage('open-options-tab').then(() => window.close(), console.error);
});
