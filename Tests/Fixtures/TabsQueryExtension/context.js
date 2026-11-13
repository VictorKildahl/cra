document.addEventListener('cra-context-request', async (event) => {
  let result;
  try {
    result = await chrome.runtime.sendMessage({ type: 'context', label: event.detail });
  } catch (error) {
    result = `error: ${error.message}`;
  }
  document.dispatchEvent(new CustomEvent('cra-context-result', { detail: result }));
});
