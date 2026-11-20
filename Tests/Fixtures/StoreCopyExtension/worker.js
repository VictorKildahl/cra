// MetaMask does this on start-up: the toolbar button opens the side panel, not the popup.
chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true });

// What the worker sees of the panel (panel.js): a tab or none behind its messages and ports,
// and how runtime.getContexts() lists it.
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.panel === 'sender') sendResponse(sender.tab ? 'tab' : 'none');
});
chrome.runtime.onConnect.addListener(async (port) => {
  if (port.name !== 'panel') return;
  const contexts = await chrome.runtime.getContexts({});
  const panel = contexts.find((c) => c.documentUrl === port.sender.url);
  const context = panel
    ? panel.contextType.toLowerCase().replace(/_/g, '') + (panel.tabId === -1 ? '' : '-in-tab')
    : 'none';
  port.postMessage({ port: port.sender.tab ? 'tab' : 'none', context });
});
