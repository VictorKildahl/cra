// The extension's own command (#701): chrome.commands.onCommand, with the page it was pressed over.
chrome.commands.onCommand.addListener(async (command, tab) => {
  const { origin } = await chrome.storage.local.get('origin');
  let n = 'none';
  try { n = new URL(tab.url).searchParams.get('n') || 'other'; } catch {}
  await fetch(`${origin}/page.html?n=commands-${command}-${n}`, { mode: 'no-cors' });
});

// A row of its own in its toolbar button's menu (#695), and what a click on it reports.
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({ id: 'cra-hello', title: 'Say hello', contexts: ['action'] });
});
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const { origin } = await chrome.storage.local.get('origin');
  let n = 'none';
  try { n = new URL(tab.url).searchParams.get('n') || 'other'; } catch {}
  await fetch(`${origin}/page.html?n=commands-menu-${info.menuItemId}-${n}`, { mode: 'no-cors' });
});
