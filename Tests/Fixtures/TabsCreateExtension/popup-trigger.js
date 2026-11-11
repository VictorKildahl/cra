const action = new URL(location.href).searchParams.get('n');
if (action === 'popup-window' || action === 'popup-fullscreen' || action === 'close-popup') {
  chrome.runtime.sendMessage(action).catch(console.error);
}
