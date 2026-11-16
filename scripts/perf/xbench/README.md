# Cross-browser bench

Cra against Helium, Arc and Dia, measured from outside the same way for every browser. Results stay out of the repo;
they go to the site only once Victor has seen them.

## Setup (once)

1. `scripts/perf/xbench/setup.sh`: tools, the bench page, Speedometer 3.1 with a score hook, the offline profile
   (all in `$XBENCH_DIR`, default `~/CraBench`).
2. A signed Cra build at `$XBENCH_DIR/Cra.app` (with the release provisioning profile) and Helium's notarized
   release at `$XBENCH_DIR/Helium.app`; Arc and Dia from /Applications, neither running.
3. `defaults export company.thebrowser.Browser` and `company.thebrowser.dia` to back them up (the offline copies
   write the real domains), then `prep.sh arc` and `prep.sh dia`: homes from the account on this Mac with nothing open.
4. `xbench.py warm <browser>` for cra, helium, arc and dia: a first launch, kept as the template every run clones,
   so "cold launch" is a launch of a browser that isn't running, not a first run.

Then `rounds.sh` (five rounds, the order rotating each round; about four hours, only while nobody uses the Mac) and
`report.py` (medians with min–max; results.json). Afterwards `defaults import` both backups.

## How each browser runs

- Offline: `sandbox-exec -f offline.sb` lets the browser reach localhost only. Arc and Dia run as copies on a fake
  home (`CFFIXED_USER_HOME`) with the account's files, and offline nothing can sync into the real account. The other
  two get the same rule so all four are alike.
- `--no-sandbox` for all four: Arc's offline copy doesn't start without it (the GPU process dies in a nested
  sandbox).
- A fresh clone of its template each session; the window set to 1440 × 900 at (100, 60) over Accessibility, then one
  click on its page area (an offline Arc's first window isn't key until clicked).
- Pages: `pages/bench.html` (60 boxes, 120 paragraphs, no timers) from `scripts/perf/server.py` on 127.0.0.1,
  which logs what each page posts: its first contentful paint, and the second animation frame after it becomes
  visible.

## A session

| Step | Measured |
|---|---|
| Launch the binary | cold launch → window on screen: the first on-screen window of the browser's process tree over 300 × 300 pt (polled every 2 ms) |
| Open tab 1 | ⌘T (⌘L where the browser opens with a blank tab), the URL set into the focused field over AX except its last character, which is typed; the field read back (and set again if it doesn't hold the URL), then Return |
| 5–25 s after | idle CPU and wakeups, 1 tab: the whole process tree (`build/perf/fp`), 20 s |
| 90–110 s after | the same, settled, and memory at 1 tab (phys_footprint, process tree) |
| Tabs 2–20 | new tab → first paint: Return to the page's first contentful paint; memory at 10 tabs 30 s after the tenth |
| 20 tabs | idle at once and settled, as for 1 tab; memory at 20 tabs |
| ⌃Tab × 10 | tab switch → shown: the Tab key's press to the shown page's second animation frame. Arc and Cra switch when Control is released (Arc's design), about 12 ms after the press here |
| ⌘W × 19 | memory back at 1 tab, 30 s after |
| ⌘N | new window → on screen |

Speedometer 3.1 runs in a session of its own (one cold launch, `?startAutomatically=true`, the score posted by
`cra-bench-hook.js`).

`xbench.py probe <browser> <dir>` is one tab, settled, with wakeups, CPU and memory per process kind
(`XBENCH_SELF=1` adds each process's own footprint): where a browser's idle and memory go.

Check each session's first tab: `marks.jsonl` holds a mark with `"n": "1"` only when tab 1 loaded the bench page.

Not measured: power (needs `sudo powermetrics`), launch → page painted and restored tabs (the browsers take a URL on
launch differently).
