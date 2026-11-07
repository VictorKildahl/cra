# Performance recorder

Cra records its own performance on the Mac it runs on (GitHub #91): main-thread stalls with
what Cra did just before, CPU and memory per process, tab timings, and how the last session
ended. Settings ▸ Performance shows it; Help ▸ Export Diagnostics adds `perf.json` and the
hang files to the zip. It is on by default in early releases, off with one switch, and nothing
leaves the Mac unless the user exports it.

## Layers

| Where | What | Imports |
|---|---|---|
| `Packages/CraCore/Sources/CraCore/Perf/` | metrics, histograms, rings, stall rules, process kinds, history, session rules, insights, the summary text, site names, the report schema | Foundation |
| `Sources/Cra/Perf/Perf.swift` | the facade the rest of the app calls: `time`, `count`, `mark`, `phase`, `begin`/`end` | Foundation |
| `Sources/Cra/Perf/` (the rest) | run-loop observer and watchdog, libproc and system samplers, files, the recorder | Foundation, Darwin |
| `Sources/Cra/Perf/PerfCEF.swift` | Chromium's process events, the visible page's long tasks, tab counts, the Settings switch | AppKit, CraCEF |
| `Sources/Cra/Perf/PerformancePane.swift` | Settings ▸ Performance | SwiftUI |

`scripts/lint.py` holds the line: `perf-no-network` rejects networking in both Perf folders,
and `perf-boundary` allows Perf calls only in the files listed under "Removing it" and
`CraCEF` only in `PerfCEF.swift`.

Data flows one way. The main thread records small facts under one lock. The watchdog thread
(2 Hz) writes a hang file itself while the main thread is blocked. One serial utility queue
samples processes and the Mac every 5 s, writes the black box every 60 s and the history every
15 minutes, and builds the export. Nothing on the main thread does file I/O, JSON encoding or
libproc calls; once every 5 s it counts tabs and asks the visible page for its long tasks.

## What a pass is

`MainLoopObserver` puts two `CFRunLoopObserver`s on the main run loop in the common modes: one
first in line when the loop wakes up (after waiting), one last in line before it sleeps (before
waiting) and when it returns to AppKit (exit). Those last two are where Core Animation commits,
so a pass is the main thread's work between two points where what it did reaches the screen:
from waking (or from the exit before it, after which AppKit handles the event the loop returned
for) to the next sleep or exit, commit included. Entering the loop and turning it without
sleeping are no boundary (GitHub #135): before, a pass ended at every observer callback, so one
turn was recorded as two halves, and a 300 ms turn of a 150 ms timer and a 150 ms block was no
stall at all. A pass differs from HitchMonitor's numbers, which time how long a block queued on
the main queue waits; that wait can span several passes.

- 250 ms or more is a stall. A stall in the default mode is a freeze: `freezes`, `longFreezes`
  (1 s or more) and `hangs` (2 s or more) count those, and `longestFreezeMs` is the longest.
- `tracking` (a held menu, a drag), `modal` (an alert, a save panel) and `launch` (from the
  recorder's start until the run loop first sleeps: AppKit runs `applicationDidFinishLaunching`
  before the loop's first pass) are loops Cra is in on purpose: their stalls are in
  `outsideFreezes`, not in the freeze counts. `longestPassMs` and `longestPassMode` are over every
  pass, the honest answer to "how long was the main thread blocked". Copy Summary and the pane
  show both.
- Stacks: at 2 s the watchdog writes `hang-<session>-<n>.json` while the hang lasts, then runs
  `/usr/bin/sample` on Cra for a second. No pass in the first real exports reached 2 s, so the
  session's first pass that is still going at 1 s (`slowStackMs`) gets one `sample` too, kept in
  memory as `mainThread.slowPass` (no file: it is no hang). At most three `sample` runs a session
  in all. `sample` takes a second to attach, so a pass that ends soon after shows mostly the idle
  run loop; `endedMs` against `stalledMs` says how much of the sample saw the block.
- Breadcrumbs are HitchMonitor's marks, cut before any `?`: swipes, page shown, page loads
  starting and ending (`load-start`, `load-end`), extension popups, scripted commands, Cra
  becoming active or not (`app-active`, `app-inactive`), full screen (`fullscreen-enter`,
  `fullscreen-exit`) and `diagnostics-export`. Every stall also says whether Cra was the active
  app and whether a window of it was on screen (`active`, `onScreen`).
- Time: `session.startedAt` is when Cra started (the top of `main.swift`), cut to the second as
  the files keep dates, and every `at` (stalls, marks, events, hang files) is seconds since then
  on the clock that counts the Mac's sleep, so `startedAt + at` lines up with `cra.log`. `uptimeSeconds` is on the
  same clock and `asleepSeconds` says how much of it the Mac slept; pass durations use the clock
  that stops in sleep, so a sleep is never a stall.

## What is recorded

Main-thread passes as a histogram, stalls with mode, breadcrumbs, the site on screen and
whether Cra was active. Per process kind (browser, renderer, GPU, utility, other, from
Chromium's `--type=` argument): CPU, memory footprint, disk reads and writes, wakeups (in the
file only), and processes started and ended. The Mac: CPU, memory pressure, thermal state, Low
Power Mode, free disk, and Cra's average CPU while nobody used the Mac (`idle`: 5-second samples
with no keyboard or mouse input for a minute). Tabs by state; tab sleeping's pages closed
(`tabSlept`), pages refusing (`sleepRefusal`, once per page and reason, then `sleepRetry` for
each ask after the back-off) and candidates passed over without being asked (`sleepSkip`:
loading, DevTools, Picture in Picture…, once per page and reason; cra.log names the site); and
timings for tab switch (without the page created for a tab that had none, which is page
create), page create, page load, waking a slept tab and framing an extension's popup. In the visible page,
read with the long tasks every 5 s and never in background tabs: long tasks, Chromium's long
animation frames (`longFrames`, `longestFrameMs`: a passive observer, it asks for no frames) and
the frames its videos played and dropped (`getVideoPlaybackQuality`). Renderer crashes, hangs
and failed loads with their codes. Start-up phases (store loaded, Chromium started, windows shown, then the first page shown,
committed and loaded), JSON load and save times (saves run on the
persistence queue, so `jsonSave` is never a main-thread stall; `fileSaved` counts the writes by
file name), the profile's and caches' size
(at export only). The session: a random id, the launch number, the previous session and whether
it quit. The totals in `tabs` are since launch; `history.json`, in the export too, has stalls
and long tasks per 5 minutes.

Never: addresses beyond the host, paths, query strings, titles, page text, form values, typed
text, an installation id. Incognito pages give counts only.

## Files

`Application Support/Cra/Perf/`, written atomically (not through `JSONStore`, which copies a
`.bak` on every save), and only by the Cra that owns the data folder:

| File | When | Size |
|---|---|---|
| `session.open` | after Chromium starts; removed on a normal quit or when recording is turned off | 200 B |
| `blackbox.json` | every 60 s and at quit: the report as of then | 5–40 KB |
| `blackbox.previous.json` | the last session's black box, moved at launch | 5–40 KB |
| `history.json` | every 15 minutes and at quit: 5-minute buckets for 24 hours, launches, the last session | up to 60 KB |
| `hang-<session>-<n>.json` | at a 2 s hang; this session's and the last one's | 1–10 KB each |

A `session.open` found at launch means that session ended without quitting (crash, force quit,
`kill -9`, power loss). It is made only after `CraCEFRuntime.initialize` succeeds, so the
"another Cra is running" and failed-start exits never leave one.

## Measured (3 Nov 2026, M-series Mac)

| | Budget | Measured |
|---|---|---|
| CPU | < 0.1 % of a core | 0.029 % (`fifty-tabs`; 2 Nov, before #135: 0.027–0.039 %) |
| Main thread | < 0.2 ms per tick | ~110 ns per observer callback (60,319 callbacks, 6.7 ms over a `fifty-tabs` run; 114,663 before #135) |
| Memory | < 5 MB | ~5 KB of recorder data (`selfCost.memoryBytes`) |
| Disk writes | < 60 KB per minute | ~5 KB per minute (black box) plus ~4 KB per minute (history) |

`selfCost` in every report says what recording cost that session, over the awake time it ran,
and which part: `observerMs`, `watchdogMs`, `processSampleMs` (libproc over every helper),
`systemSampleMs`, `filesMs` (black box and history: building, encoding, writing) and
`mainSamplerMs` (the tab count and the visible page's read on the main thread).
`scripts/scenario.sh` fails a scenario above 0.1 %, and a report above it says so in its
findings (`profiler-overhead`); the numbers still hold, the finding is there so a report says
what recording cost.

The first real exports (GitHub #135: 2 500 tabs, 9 loaded, 3 hours) measured 0.13–0.145 %,
against 0.03 % on `fifty-tabs`. Most of it was the 5-second queue, not the observer (536 ms of
6 342), and the observer's callbacks were twice what they needed to be (one record per
callback). The callbacks are halved (#135); the parts above say where the rest goes on the next
real export. On `fifty-tabs` the 13.5 ms were: observer 6.7, process sample 5.1 (libproc and the
`--type=` of each new renderer), main sampler 1.0, watchdog 0.4, system sample 0.3, files 0.1.

## Spikes (phase 0)

- **Run-loop observer and modes**: works in the common modes. Found that the launch work runs
  before the first pass and would be missed; it is now measured as a `launch` pass.
- **libproc on helpers**: `proc_listchildpids` returns a pid count; `proc_pid_rusage` reads
  every helper of an ad-hoc hardened-runtime build (no task port needed); `ri_*_time` is in
  mach ticks (×125/3 ns on Apple silicon). CEF runs its GPU process from the plain helper app,
  so kinds come from `--type=` (`KERN_PROCARGS2`), not the app name.
- **`sample` on a release build**: works from the app on itself under the hardened runtime,
  with readable Swift and Objective-C symbols even after `strip` (e.g. `AppDelegate.handleInternalURL(_:)` → `usleep`).
  It takes about 2 s for a 1 s sample, so it runs on the watchdog thread after the hang file
  is written. A notarized Developer ID build still needs a check on the first release.
- **Isolated-world long tasks**: a `PerformanceObserver` in Cra's isolated world receives the
  page's long tasks. Chromium reports none while a page is hidden, so a covered window counts
  nothing (test copies run with `--disable-backgrounding-occluded-windows`).
- **Not done (phase 2)**: Chromium's histograms over CDP, a renderer-side route for
  process-to-tab mapping.

## Testing

- `swift test --package-path Packages/CraCore`: histograms, rings, stall rules, site names,
  sessions, history, process churn, the `sample` parser, insights, the summary and the golden
  `Fixtures/Perf/perf-golden.json` (re-record with `CRA_RECORD_GOLDEN=1`).
- `scripts/test-perf.sh`: the recorder on a real main run loop: injected stalls with their
  breadcrumbs, a hang file on disk before the main thread returns, with a real `sample` stack,
  the marker after a quit and after a simulated kill, a second Cra writing nothing, recording
  off writing nothing.
- `cra://debug?stall=<ms>` blocks the main thread; `cra://debug?perfReport=<path>` writes the
  report now.
- `CRA_PERF=0` turns recording off for a development run.

## Removing it

1. Delete `Sources/Cra/Perf/`, `Packages/CraCore/Sources/CraCore/Perf/`, their tests
   (`Tests/PerfTests.swift`, `scripts/test-perf.sh`, the `Perf*` and `SiteNames` tests and
   `Fixtures/Perf` in CraCore) and the `Perf recorder` line in `scripts/test.sh`.
2. Remove the calls in the files `perf-boundary` allows: `App/main.swift`, `App/AppDelegate.swift`
   (`PerfCEF.install`, the `stall` and `perfReport` hooks, `exportDiagnostics` in the settings
   actions), `Services/BrowserManager.swift`, `Services/Persistence.swift`,
   `Services/HitchMonitor.swift`, `Services/Diagnostics.swift`, `Services/ExtensionActions.swift`
   (the popup's `Perf.time`), `UI/Settings/SettingsWindowController.swift`
   (the pane, `isOpen`). Then the two rules in `scripts/lint.py`.
3. `CraLog.sitesSeen` and `SiteNames` serve "Hide site names"; keep them if that stays.
4. The `lt` and `lf` observers in `PageScript.isolatedWorld`, the `load-start`/`load-end` and
   `diagnostics-export` marks, and `setProcessEventHandler` in CraCEF.
5. `perfRecording` and `perfHidesSiteNames` in `AppSettings` (old files keep loading: unknown
   keys are ignored) and their lines in `Fixtures/Model`.
6. The harness lists that compile `Perf.swift` and `CraCore/Perf/*.swift`
   (`Tests/test-browser-manager.sh`, `scripts/test-store.sh`, `scripts/fuzz.sh`), and the
   perf invariant in `scripts/scenario.sh`.
