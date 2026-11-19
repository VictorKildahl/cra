// chrome.action.openPopup() from the page's request: the popup has to open in the window the page is in.
chrome.runtime.onMessage.addListener((message, sender) => {
  if (!sender.tab || (message !== 'open-popup' && message !== 'open-popup-window')) return;
  const origin = new URL(sender.tab.url).origin;
  (async () => {
    let result = 'opened';
    try {
      await chrome.action.openPopup(message === 'open-popup-window' ? { windowId: sender.tab.windowId } : undefined);
    } catch (e) {
      result = 'error-' + String(e.message || e).toLowerCase().replace(/[^a-z]+/g, '-');
    }
    await fetch(`${origin}/page.html?n=openpopup-${message}-${result}`).catch(console.error);
  })();
});
