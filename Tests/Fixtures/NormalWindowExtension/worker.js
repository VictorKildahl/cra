// GitHub #578: an extension makes a normal window on about:blank and goes on using its id, as BrowserSkill's
// Agent Window does. In Chrome the id names a window until the extension (or the user) closes it. Cra keeps
// the window out of sight, but the id has to keep working: windows.get finds it, windows.getAll lists it,
// tabs.create puts a tab in it, tabs.query finds that tab there and windows.remove closes it (onRemoved fires).
// A normal window on a page is the other case: its page becomes a Cra tab and Chrome's window closes.
const settle = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

chrome.runtime.onMessage.addListener((message, sender) => {
  if (message !== 'normal-window' || !sender.tab) return;
  const origin = new URL(sender.tab.url).origin;
  (async () => {
    const answers = [];
    let removed = false;
    let blank = null;
    chrome.windows.onRemoved.addListener((id) => {
      if (blank && id === blank.id) removed = true;
    });
    blank = await chrome.windows.create({ type: 'normal', focused: false, url: 'about:blank' });
    // Past the bridge's look at the window's pages, which ran right after Chrome made it.
    await settle(1000);
    answers.push('get-' + await chrome.windows.get(blank.id).then((w) => (w.id === blank.id ? 'ok' : 'other'), () => 'missing'));
    answers.push('listed-' + (await chrome.windows.getAll()).some((w) => w.id === blank.id));
    const tab = await chrome.tabs.create({ windowId: blank.id, url: `${origin}/page.html?n=in-window`, active: true })
      .then((t) => (t.windowId === blank.id ? 'ok' : 'elsewhere'), () => 'error');
    answers.push('tab-' + tab);
    answers.push('query-' + (await chrome.tabs.query({ windowId: blank.id })).length);
    answers.push('remove-' + await chrome.windows.remove(blank.id).then(() => 'ok', () => 'error'));
    await settle(500);
    answers.push('removed-' + removed);

    const page = await chrome.windows.create({ type: 'normal', focused: false, url: `${origin}/page.html?n=adopted` });
    await settle(1000);
    answers.push('adopted-' + await chrome.windows.get(page.id).then(() => 'open', () => 'closed'));
    await fetch(`${origin}/page.html?n=normal-window-${answers.join('-')}`).catch(console.error);
  })();
});
