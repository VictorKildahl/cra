// The cross-browser bench's hook: posts the score once Speedometer shows it.
setInterval(() => {
  const e = document.getElementById("result-number"), v = e && e.textContent.trim();
  if (v && /^[0-9.]+$/.test(v) && !window.__posted) {
    window.__posted = 1;
    fetch("/mark", { method: "POST", body: JSON.stringify({ kind: "sp3", n: "sp3", t: Date.now(), v }) });
  }
}, 1000);
