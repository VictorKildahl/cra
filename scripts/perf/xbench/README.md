# Cross-browser bench

How Cra's speed and memory numbers are measured, against Helium, Arc and Dia and against older Cra releases, so
anyone with a Mac can run the same bench and check them. Every browser is measured from outside, the same way:
the bench launches it, drives it with keys, reads its windows over Accessibility and sums its processes' memory, CPU
and wakeups. Nothing in a browser reports its own numbers. Results stay out of the repo.

## What you need

- A Mac with Apple silicon. Absolute numbers depend on the Mac, so compare browsers measured on the same Mac,
  not your numbers against ours.
- Xcode's command line tools (`xcrun swiftc`), Python 3, `git`, and `cliclick` (`brew install cliclick`).
- Accessibility permission for the terminal you run it from (System Settings ▸ Privacy & Security ▸
  Accessibility): the bench sizes windows, types and reads the address field over Accessibility.
- The browsers:
  - Cra: a signed build or a release from GitHub, copied to `$XBENCH_DIR/Cra.app`.
  - Helium: its notarized release, copied to `$XBENCH_DIR/Helium.app`.
  - Arc and Dia: installed in /Applications and signed in to an account. The bench runs offline copies of them on a
    fake home (below), so the account sees nothing.
  - Optional: Google Chrome in /Applications, as a Speedometer reference, and an older Cra release (below).
- About four hours with nobody at the Mac for the full run. Every run waits until there has been no keyboard or
  mouse input for 30 s, and stops being valid if someone uses the Mac during it.

`$XBENCH_DIR` is the bench folder (default `~/CraBench`).

## Setup (once)

1. `scripts/perf/xbench/setup.sh`. It builds the helper tools and `build/perf/fp` (the meter, below), copies the
   bench page and the offline profile, and clones Speedometer 3.1 (WebKit's `release/3.1` branch) with a score hook.
   Everything goes in `$XBENCH_DIR`.
2. Back up Arc's and Dia's preferences: `defaults export company.thebrowser.Browser arc.plist` and
   `defaults export company.thebrowser.dia dia.plist`. The offline copies write the real preference domains (macOS
   ignores the fake home for those). `defaults import` both after the bench.
3. `prep.sh arc` and `prep.sh dia`: each offline copy's home, made from the account on this Mac with nothing open.
   Arc keeps its default space with its folders emptied; Dia keeps its profile without tabs, pinned tabs, sessions,
   extensions or caches.
4. `xbench.py warm <browser>` once for each browser you'll measure (`cra`, `helium`, `arc`, `dia`, plus `chrome`
   or `craold` if used). This is a first launch, kept as the template that every run starts from, so "cold launch"
   means launching a browser that isn't running, not a first run.

## Conditions

These change the numbers, so keep them the same for every browser:

- **No other browser running.** That includes your own copy of Cra: an older Cra seeing another Cra running skips
  some of its start-up work (it doesn't own the data folder), which makes it look lighter.
- **The Mac's built-in display only.** Window memory grows with the screen's size and pixel depth: the same build
  used about 80 MB less at one tab, and about 300 MB less at 10 tabs, on a 2560 × 1440 external display than on the
  MacBook's own. Each run saves `end.png`, so you can check its size afterwards.
- **On power, the display awake and the session unlocked** (`caffeinate -d` while it runs). Pages in a hidden or
  locked session don't draw frames, and their measurements come back empty.
- **The same time of day where you can.** Arc's memory was 40–80 MB lower at night than in the evening (Helium's
  and Dia's weren't). Speedometer scores drift with the Mac's temperature, so compare Speedometer scores only from
  the same hour (`speedometer.sh`).

## Running it

| Command | What it does |
|---|---|
| `rounds.sh` | Five rounds of Cra, Helium, Arc and Dia, the order rotating each round. Each round is one measured session (below) and one Speedometer session per browser. Results go to `$XBENCH_DIR/results` (`<browser>-<round>` and `sp-<browser>-<round>`). Run it again to fill in sessions that failed; finished ones are kept. |
| `rounds.sh cra craold` | The same for any list of browsers. |
| `speedometer.sh [browser...]` | Speedometer only: the browsers one after another, three rounds, all in the same hour. Defaults to `cra craold helium chrome`. Scores go to `results-speedometer/scores.txt`. |
| `report.py [dir]` | Medians with min–max per browser, as a table and `results.json`. `XBENCH_NAMES="craold cra"` picks the browsers. |
| `xbench.py session\|speedometer\|probe <browser> <dir>` | One run. |

`XBENCH_OUT` puts results in another folder. `XBENCH_CRA_APP` measures another Cra build than `Cra.app`.
`XBENCH_CRA_ARGS` adds command-line switches to Cra, for example `--disable-features=<Feature>`.

### Against an older Cra

1. Download `Cra.dmg` from the release's page (for example
   https://github.com/VictorKildahl/cra/releases/tag/v0.1.41).
2. Copy its app to `$XBENCH_DIR/Cra-old.app`, or point `XBENCH_CRA_OLD_APP` at it.
3. `xbench.py warm craold`.
4. `XBENCH_OUT=$XBENCH_DIR/results-old rounds.sh craold cra`.
5. `XBENCH_NAMES="craold cra" report.py $XBENCH_DIR/results-old`.

Both Cras run on a data folder of their own (`CRA_DATA_DIR`), cloned from their templates, with iCloud sync pointed
at an empty folder.

## How each browser runs

- **Offline.** `sandbox-exec -f offline.sb` lets the browser reach localhost only.
  - Arc and Dia run as copies on a fake home (`CFFIXED_USER_HOME`) with the account's files. Offline, nothing can
    sync into the real account.
  - The other browsers get the same rule, so all are alike.
- **`--no-sandbox` for every browser.** Arc's offline copy doesn't start without it: the GPU process dies in a
  nested sandbox.
- **A fresh copy of its template each session.** The window is set to 1440 × 900 at (100, 60) over Accessibility,
  then clicked once on its page area, because an offline Arc's first window isn't key until clicked.
- **Pages are local.** `pages/bench.html` (60 boxes, 120 paragraphs, no timers) and Speedometer come from
  `scripts/perf/server.py` on 127.0.0.1. The server logs what each page posts:
  - its first contentful paint;
  - the second animation frame after the page becomes visible;
  - Speedometer's score.

## The meter

`build/perf/fp <pid>` (`scripts/perf/fp.swift`) sums over the browser's process tree: the browser and every process
it started, helpers included.

| Reported | Source |
|---|---|
| Memory | `ri_phys_footprint` (what Activity Monitor calls Memory), in MiB |
| CPU | user plus system time |
| Wakeups | package idle wakeups plus interrupt wakeups |

Idle CPU and wakeups are the difference between two readings 20 s apart.

## A session

| Step | Measured | Row in report.py |
|---|---|---|
| Launch the binary | Launch to the first on-screen window of the browser's process tree over 300 × 300 pt (polled every 2 ms) | cold launch → window on screen |
| Open tab 1 | ⌘T (⌘L where the browser opens with a blank tab). The URL goes into the focused field over Accessibility, all but its last character, which is typed. The field is read back (and set again if it doesn't hold the URL), then Return | – |
| 5–25 s after | Idle CPU and wakeups, 1 tab | idle CPU / wakeups, 1 tab |
| 90–110 s after | The same again once settled, and memory | … settled; memory, 1 tab |
| Tabs 2–20 | Return to the page's first contentful paint, for each tab; memory 30 s after the tenth | new tab → first paint (median of 19); memory, 10 tabs |
| 20 tabs | Idle at once and settled, as for 1 tab | memory, 20 tabs; idle at 20 tabs |
| ⌃Tab × 10 | The Tab key's press to the shown page's second animation frame. Arc and Cra switch when Control is released (Arc's design), about 12 ms after the press here | tab switch → shown (median) |
| ⌘W × 19 | Memory at 1 tab again, 30 s after | memory, back to 1 tab after 20 |
| ⌘N | New window to on screen | new window → on screen |

The idle and memory rows published are the settled ones (90–110 s after).

Speedometer 3.1 runs in a session of its own: one cold launch, then
`speedometer/index.html?startAutomatically=true`, with the score posted by `cra-bench-hook.js`.

`xbench.py probe <browser> <dir>` is one tab, settled, with wakeups, CPU and memory per process kind
(`XBENCH_SELF=1` adds each process's own footprint): where a browser's idle time and memory go.

## Checking a run

- **A session counts only if tab 1 loaded the bench page.** `marks.jsonl` holds a mark with `"n": "1"`, and
  `result.json` has `first_tab_fcp_ms`. Now and then a browser's address bar takes Return before it has caught up
  with the URL and searches instead. `report.py` also skips sessions without `tab_switch_shown_ms`.
- **`end.png` is the screen at the end:** it shows the display the run was on.
- **`log.txt` has every reading with its time.**

## Not measured

- Power: it needs `sudo powermetrics`.
- Launch to a painted page, and restored tabs: the browsers take a URL at launch differently.

## The published numbers

Measured 15–16 Nov 2026 on a MacBook Pro (M2 Max, 32 GB, macOS 26.7.2), on its built-in display and on power.

| Browser | Version | When |
|---|---|---|
| Cra | main at 0ea81232, engine 158.0.8127.37-9 | sessions 16 Nov, morning |
| Cra (Speedometer) | the build before it (4cf04e29, the same engine binary; 0ea81232 only changes how the window draws its grain) | night of 15–16 Nov, and 16 Nov morning with the others below |
| Helium | 0.21.3.1 (Chromium 157.0.8103.78) | 15 Nov, evening |
| Arc | 1.173.1 | night of 15–16 Nov |
| Dia | 1.57.1 | 15 Nov, evening |
| Cra 0.1.41 | the GitHub release `Cra.dmg`, CEF 156.0.27 | 16 Nov, morning |
| Google Chrome | 157.0.8103.79 | 16 Nov, morning (Speedometer only) |

Cra 0.1.41 (12 Nov) is the last release before the work on speed and memory. Its first two rounds ran on an
external 2560 × 1440 display, so its numbers are the medians of rounds 3–5. Those three rounds ran on the built-in
display, like the other browsers.

The Speedometer comparison of Cra, Cra 0.1.41, Helium and Chrome comes from `speedometer.sh`: three rounds, all in
one 15-minute window. Arc's and Dia's Speedometer scores come from their `rounds.sh` sessions.

An installed Cra (0.1.43) was running during the 0.1.41 rounds. 0.1.41 skips some of its start-up work when
another Cra is running, so its numbers are if anything lower than they would be alone, which makes the improvement
measured since then smaller, not larger.
