if (new URL(location.href).searchParams.get('n') === 'focus-window') {
  chrome.runtime.sendMessage('focus-window').catch(console.error);
}
