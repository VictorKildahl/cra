// A page whose address has n=debugger gets the debugger attached, which shows Chrome's
// "Cra Debugger Fixture started debugging this browser" bar above every page; n=detach lets go,
// and the bar goes away.
chrome.tabs.onUpdated.addListener((tabId, info, tab) => {
  if (info.status !== "complete" || !tab.url) return;
  if (tab.url.includes("n=debugger")) chrome.debugger.attach({ tabId }, "1.3", () => void chrome.runtime.lastError);
  if (tab.url.includes("n=detach")) chrome.debugger.detach({ tabId }, () => void chrome.runtime.lastError);
});
