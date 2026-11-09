document.getElementById('close').addEventListener('click', () => window.close());

// What the panel is to its extension (#265). In Chrome a side panel page is not a tab:
// tabs.getCurrent() gives undefined, the worker sees no sender.tab on the panel's messages and
// ports, and runtime.getContexts() lists the panel as SIDE_PANEL with no tab. Claude in
// Chrome's panel refuses to start, and its worker refuses the panel's bridge, unless that holds.
// The scenario reads `answers` (cra://debug?sidePanelJS=answers).
var answers = 'pending';
(async () => {
  const current = (await chrome.tabs.getCurrent()) ? 'tab' : 'none';
  const message = await chrome.runtime.sendMessage({ panel: 'sender' });
  const port = chrome.runtime.connect({ name: 'panel' });
  port.onMessage.addListener(({ port: portSender, context }) => {
    answers = `current-${current}-message-${message}-port-${portSender}-context-${context}`;
  });
})();
