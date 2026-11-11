const action = new URL(location.href).searchParams.get('n');
if (action === 'popup-window' || action === 'close-popup') {
  chrome.runtime.sendMessage(action).catch(console.error);
}
