// The extension's own command (#701): chrome.commands.onCommand, with the page it was pressed over.
chrome.commands.onCommand.addListener(async (command, tab) => {
  const { origin } = await chrome.storage.local.get('origin');
  let n = 'none';
  try { n = new URL(tab.url).searchParams.get('n') || 'other'; } catch {}
  await fetch(`${origin}/page.html?n=commands-${command}-${n}`, { mode: 'no-cors' });
});
