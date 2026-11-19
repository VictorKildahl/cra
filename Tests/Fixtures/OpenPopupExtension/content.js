const n = new URL(location.href).searchParams.get('n');
if (n === 'open-popup' || n === 'open-popup-window') {
  chrome.runtime.sendMessage(n).catch(console.error);
}
