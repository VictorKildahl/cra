// Loads a fixture page to say ⌘⇧Y, typed in a page, opened the popup (#744).
chrome.storage.local.get('origin').then(({ origin }) => fetch(`${origin}/page.html?n=page-shortcut-popup-opened`, { mode: 'no-cors' }));
