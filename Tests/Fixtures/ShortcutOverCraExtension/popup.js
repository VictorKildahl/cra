// Loads a fixture page to say ⌘⇧O opened the popup (#744).
chrome.storage.local.get('origin').then(({ origin }) => fetch(`${origin}/page.html?n=shortcut-over-cra-popup-opened`, { mode: 'no-cors' }));
