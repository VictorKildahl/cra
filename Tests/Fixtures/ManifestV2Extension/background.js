// Cancels every request whose address holds "cra-mv2-probe". Only a running Manifest V2
// extension can: blocking webRequest listeners are gone from Manifest V3.
chrome.webRequest.onBeforeRequest.addListener(
  () => ({ cancel: true }),
  { urls: ["http://127.0.0.1/*cra-mv2-probe*"] },
  ["blocking"]
);
