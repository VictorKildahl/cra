if (new URL(location.href).searchParams.get('n') === 'normal-window') {
  chrome.runtime.sendMessage('normal-window').catch(console.error);
}
