// Reloads this copy once, as chrome.runtime.reload() or chrome://extensions does: Chromium loads the folder
// again, and every observer hears an install of this ID that isn't the store's.
chrome.storage.local.get("reloaded").then(({ reloaded }) => {
  if (reloaded) return;
  chrome.storage.local.set({ reloaded: true }).then(() => setTimeout(() => chrome.runtime.reload(), 3000));
});
