// The active tab goes to another app's address, as Obsidian Web Clipper's "Add to Obsidian" does (#785).
chrome.tabs.query({ active: true, currentWindow: true }).then(([tab]) =>
  chrome.tabs.update(tab.id, { url: 'macappstore://apps.apple.com/app/id1?n=extension' }));
