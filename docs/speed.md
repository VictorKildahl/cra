# Speed: where Cra stands and what the next gains need

How fast Cra is against other Chromium browsers on this kind of Mac, what was done about it, and what
each of the next gains needs before it can happen. [performance.md](performance.md) is the recorder
that measures Cra on users' Macs; this is the lab side.

## Measuring

`scripts/perf/bench.sh` measures one build from outside the app, on a local bench page, in a
background copy with its own data folder; `scripts/perf/rounds.sh` interleaves several builds;
`scripts/perf/report.py` prints the table. The script headers say what each row is.

```sh
caffeinate -d scripts/perf/rounds.sh build/perf/gate 2 before=/tmp/before/Cra.app after=build/Cra.app
python3 scripts/perf/report.py build/perf/gate/*-[0-9]*
```

- **Interleave, and compare ranges.** The same build moves 10–20 % between runs on a Mac in use
  (Trend Micro, other builds, agents). Runs of the two builds alternate, and a row is different only
  when the min–max ranges separate. One run that disagrees with another is noise, not a finding.
- **The before build gets the same test-mode code.** Build it from the base commit plus any change to
  `HitchMonitor` the after build has, so only the change under test differs.
- **The windows need frames.** Test copies open on `CRA_TEST_SCREEN`. A display asleep or showing
  another Space gives them none: no switch is ever "shown" (report.py's "switches shown" row) and the
  GPU process reads as a hidden browser's. `caffeinate -d`, a display that's on, and rerun when a
  switch is missing.
- **Idle rows need a quiet window.** The command-file poll (6.7 wakeups/s) is in every test copy and
  not in users' Cra; HitchMonitor (~250/s) is only in the latency launch.
- **A count that went down is not a speed-up** until a timed run shows it. Changes that saved nothing
  measurable come out again (the sidebar press's frame-clock wake, purge on freeze: below).

## Where it stands (12 Nov 2026, M2 Max, 20 bench tabs)

Against main the same day (interleaved runs):

| | Before | After this round |
|---|---|---|
| Idle wakeups, 20 tabs | 82–93 /s | 69–71 /s |
| GPU process, 20 tabs | 237 MB | 162 MB |
| Total memory, 20 tabs | ~1,200 MB | ~1,150 MB |
| Tab switch → shown | 15–17 ms | 12–15 ms (same within noise) |

Against another Chromium-based Arc-style browser on Chromium 157 with its own engine layer (no CEF),
same page and steps: Cra is ahead on idle CPU and even on idle wakeups, and behind on memory, ~1,150
against ~930 MB at 20 tabs and ~370 against ~320 MB back at one tab. Where the difference is:

| | Cra | The other browser | Why |
|---|---|---|---|
| Page processes | ~33 MB each | ~26.5 MB each | The engine version: 157 there, 156 here. Cra's own page scripts are 0.6 MB of it (measured). |
| Browser process | ~210 MB | ~155 MB | CEF makes every tab a Chrome browser with its own (hidden) window and toolbar. |
| GPU | ~160 MB | (with network, storage, its blocker: ~250 MB) | Even now that five hidden tabs keep their frame. |

## Done this round

- **Tab freezing past the five tabs used last** (Chromium's InfiniteTabsFreezing, CraCEF.mm): frozen
  and thawed 5 s a minute, unless playing, capturing, holding a lock, using WebRTC or a device, allowed
  to notify, or holding a live connection. Most of the wakeup drop.
- **A page with a WebSocket or WebTransport connection is never frozen**
  (`page-live-connections.patch`, `freezing-live-connection.scenario`). A freeze closes its sockets,
  so before this a chat tab out of sight 30 minutes lost its connection.
- **Hidden tabs keep five frames, not ten** (ScalableFrameEviction off, `HiddenFrameRelease`): −75 MB
  of GPU memory at 20 tabs.
- **Closed tabs' memory goes back** (`Cra.reclaimMemory`, `MemoryReclaim`): the browser process's
  allocator returns freed pages 5 s after the last close.
- **No Touch ID check per new page** (AutofillAiWalletPrivatePasses off): a synchronous
  LocalAuthentication call before every page's first navigation. Not measurable in the bench.
- **The first launch after an update** (`UpdatePrewarm`): macOS checks a bundle it hasn't run before,
  2–3 s before any of Cra's code runs; the staged update now runs once, hidden, beforehand. Not
  measured on Cra yet: compare the first launch of a fresh copy of the notarized app with one that
  was started once and killed (`CRA_PREWARM=1` exits at the top of main.swift).

Tried and taken out: waking Chromium's frame clock on a sidebar press (no gain: Cra's pages keep
their frame while hidden), and MemoryPurgeOnFreeze (no memory saved on these pages, and idle CPU
went up with tabs refreezing every minute).

## The next gains

In order of what they're worth.

### 1. What users feel: making a page costs ~34 ms of the main thread

`scripts/perf/journeys.sh` times what a user waits for on a copy of a real sidebar (12 Nov 2026: 2
spaces, 96 items) and real sites; `journeys.py` prints it. Main-thread stall per action, median:

| Action | To page shown | Stalls |
|---|---|---|
| Tab switch | 30 ms | 75 ms |
| Open a site | 36 ms | 83 ms |
| Space switch | 15 ms | 57 ms |
| Close tab | 6 ms | 39 ms |
| Sidebar toggle | – | 30 ms |
| Command bar keystroke | – | ~0 ms |

The performance recorder (a copy with its own bundle id, so it owns its profile) splits a switch:
the switch itself ~9 ms, making the page for a tab that has none (a new tab, a link opened in a tab,
the first visit to a restored tab) **34 ms on average, up to 104 ms** (`pageCreate`), the rest the
page's load handled on the main thread, as in Chrome. The page's cost is CEF making a whole macOS
window per tab: NSWindow creation, Chromium asking the window server twice whether it is on the
active Space, and `ChromiumDialogs.patch`'s hook on `makeKeyAndOrderFront` (one more window-server
round trip). Two ways to take it off the click:

- **A spare page**, made in idle time and taken by the next tab that needs one (`BrowserManager.adopt`
  already hands a live page to a tab; a page made with a saved history starts with no address, as a
  spare would). The catch: in CEF every page is a Chrome tab, so extensions would see the spare
  (`chrome.tabs`) unless it is hidden from them until it is taken.
- **Leaving CEF** (3 below): a Chrome tab is a WebContents in an existing window, no new window.

Both done since: **spare pages** (SparePages; extensions don't see the spare, spare-pages.scenario) took
page making from 34 to 21 ms on average, the switch to a restored tab's page shown from 30 to 12 ms
and opening a site from 36 to 16 ms; and **tabs switch on the press**, as Arc does (checked on live Arc
1.173.1), which takes the click's own length (typically ~90 ms) off every sidebar switch.

### 2. A newer Chromium (page processes, ~7 MB a page)

CEF skipped 157: its master went from 156 to 158 (158.0.8127.0, 4 Nov 2026) and only 156 has a
release branch (8078). The daily CEF update check opens the issue when a stable 158 branch exists;
take it with `scripts/update-cef.sh` as soon as it does, and measure the page processes against 156.
Every engine round also needs the Intel build ([release.md](release.md)).

### 3. Leave CEF (browser process, ~50 MB at 20 tabs; any Chromium version)

Build Chrome's own framework with a thin Cra layer instead of CEF: one Chrome browser per profile
and window instead of one per tab, no hidden toolbar per tab, and Cra picks its Chromium version
instead of waiting for CEF's branches.

- **Shape**: a second implementation of the CraCEF bridge (`Sources/CraCEF/include/`) on
  `//chrome:chrome_framework`, so the Swift app doesn't change, in its own app build, switched over
  in one go once it does everything the CEF one does. The two can't share a process (each is a whole
  Chromium).
- **What carries over**: the codecs are GN arguments (`proprietary_codecs`, `ffmpeg_branding`). About
  18 of the 28 `scripts/cef-patches` change Chrome's own code (extensions, fingerprinting, speech,
  translate, the keychain, freezing) and come along; about 10 fix CEF itself (popups, downloads
  without a CEF browser, audible state, Cra.* DevTools methods) and become the layer's own code.
- **Acceptance**: `scripts/test.sh`, every scenario and `Tests/promises.lock` on the new build.
- **First step**: a one- to two-day spike, a bare host app on the Chrome framework that loads a page
  in two profiles, takes a popup as a Cra tab, shows an extension popup and quits cleanly. Go or no-go
  from that, before any migration.
- **Before starting**: a second Chromium checkout and build needs ~80 GB beside the CEF checkout,
  which has to stay until the switch (30 GB were free on 12 Nov). Free the space or use an external
  disk.
