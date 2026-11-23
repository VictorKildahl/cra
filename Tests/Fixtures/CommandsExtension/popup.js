// Loads a fixture page to say the shortcut opened the popup (#701).
chrome.storage.local.get('origin').then(({ origin }) => fetch(`${origin}/page.html?n=commands-popup-opened`, { mode: 'no-cors' }));
