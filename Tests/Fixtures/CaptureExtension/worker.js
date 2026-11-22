// GoFullPage's toolbar button (GitHub #621): on a click, run a script in the page (it scrolls and measures), capture
// the visible tab as a PNG, keep it, and open the extension's own result page in a new tab, which reads it back and
// reports to the fixture server: <page>?n=capture-<ok|failed>-<the page's n>-<png|step>.
chrome.action.onClicked.addListener(async (tab) => {
  const origin = new URL(tab.url).origin, from = new URL(tab.url).searchParams.get('n') || 'page';
  let step = 'script';
  try {
    const [{ result: height }] = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => { window.scrollTo(0, 0); return document.documentElement.scrollHeight; },
    });
    step = 'capture';
    const shot = await chrome.tabs.captureVisibleTab(tab.windowId, { format: 'png' });
    step = 'store';
    await chrome.storage.session.set({ shot, origin, from, height });
    step = 'open';
    await chrome.tabs.create({ url: chrome.runtime.getURL('result.html'), index: tab.index + 1 });
  } catch (e) {
    await fetch(`${origin}/page.html?n=capture-failed-${from}-${step}`, { mode: 'no-cors' }).catch(() => {});
  }
});
