(async () => {
  const opened = await chrome.windows.getCurrent();
  await chrome.windows.update(opened.id, { width: 420 });
  const current = await chrome.windows.getCurrent();
  document.title = current.id === opened.id && current.type === 'popup' && current.width === 420
    ? 'Popup fixture: id-type-resize-preserved' : 'Popup fixture: failed';
})();
