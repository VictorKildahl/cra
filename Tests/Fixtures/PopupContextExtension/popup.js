// ZeroOmega's popup (#699): the active tab of the popup's window and of the last focused one. Each is
// named by its page's ?n=, "none" when the query finds no tab.
(async () => {
  const { origin } = await chrome.storage.local.get('origin');
  const n = (tab) => { try { return new URL(tab.url).searchParams.get('n') || 'other'; } catch { return 'none'; } };
  const [current] = await chrome.tabs.query({ active: true, currentWindow: true });
  const [last] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  await fetch(`${origin}/page.html?n=popup-context-current-${n(current)}-last-${n(last)}`, { mode: 'no-cors' });
})();
