// GitHub #503: an extension asks for the window of a tab behind to be focused, again and again.
chrome.runtime.onMessage.addListener((message, sender) => {
  if (message !== 'focus-window' || !sender.tab) return;
  const origin = new URL(sender.tab.url).origin;
  (async () => {
    for (let i = 1; i <= 3; i++) {
      await chrome.windows.update(sender.tab.windowId, { focused: true }).catch(console.error);
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
    await fetch(`${origin}/page.html?n=focused-3`).catch(console.error);
  })();
});
