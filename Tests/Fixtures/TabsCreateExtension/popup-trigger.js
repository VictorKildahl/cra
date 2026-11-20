const action = new URL(location.href).searchParams.get('n');
if (action === 'popup-window' || action === 'popup-fullscreen' || action === 'close-popup' || action === 'badge'
    || action === 'settings-popup-worker' || action === 'settings-popup-runtime') {
  chrome.runtime.sendMessage(action).catch(console.error);
}
