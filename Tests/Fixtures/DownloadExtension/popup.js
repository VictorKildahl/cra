// Saves a file from the popup document as soon as it opens, the way an extension's
// "Download" button does: chrome.downloads with a blob: address made here (GitHub #218).
const url = URL.createObjectURL(new Blob(["Cra download fixture\n"], { type: "text/plain" }));
chrome.downloads.download({ url, filename: "cra-popup-download.txt", saveAs: false })
  .then(() => { document.body.textContent = "Saved"; })
  .catch((e) => { document.body.textContent = "Failed: " + e.message; });
