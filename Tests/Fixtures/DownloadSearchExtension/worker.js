// A download manager extension lists the downloads (chrome.downloads.search), and Chrome then checks that the
// file of every finished download is still on disk (DownloadManager::CheckForHistoryFilesRemoval, at most every
// 10 s). One that's gone is updated as removed, so Cra hears from a download of an earlier launch (GitHub #519).
//
// Each file this extension sees finish is deleted (chrome.downloads.removeFile), so after a relaunch the download
// is in Chrome's history without its file. Each page that finishes loading on the fixture server is answered with
// a search, reported as <origin>/page.html?n=downloads-<count>-gone-<count whose file Chrome found gone>.
chrome.downloads.onChanged.addListener((delta) => {
  if (delta.state?.current === 'complete') chrome.downloads.removeFile(delta.id).catch(() => {});
});

chrome.tabs.onUpdated.addListener(async (tabId, change, tab) => {
  if (change.status !== 'complete' || !tab.url?.startsWith('http://127.0.0.1')) return;
  const items = await chrome.downloads.search({});
  const gone = items.filter((d) => d.state === 'complete' && !d.exists).length;
  fetch(`${new URL(tab.url).origin}/page.html?n=downloads-${items.length}-gone-${gone}`, { mode: 'no-cors' }).catch(() => {});
});
