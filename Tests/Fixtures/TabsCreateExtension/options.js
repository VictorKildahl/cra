// The options page (GitHub #626, #631) says it opened, for the scenario that opens it from the popup.
chrome.storage.session.get('settings').then(({ settings }) => {
  if (settings) fetch(`${settings.origin}/page.html?n=settings-options-${settings.how}`, { mode: 'no-cors' });
});
