// The result page GoFullPage opens: shows the capture and tells the fixture server how big it was.
chrome.storage.session.get(['shot', 'origin', 'from']).then(({ shot, origin, from }) => {
  document.getElementById('shot').src = shot || '';
  const bytes = shot ? Math.round(shot.length * 3 / 4) : 0;
  fetch(`${origin}/page.html?n=capture-${bytes > 1000 ? 'ok' : 'failed'}-${from}-${bytes > 1000 ? 'png' : 'empty'}`, { mode: 'no-cors' });
});
