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
first in line when a pass starts (entry, after waiting, before timers), one last in line when
it ends (before waiting, exit), so Core Animation's commit counts. A pass is the time between
two points where the main thread could take input. It differs from HitchMonitor, which times
how long a block queued on the main queue waits; that wait can span several passes. On
`fifty-tabs` both see the same number of 250 ms stalls, give or take one.

- 250 ms or more is a stall, 1 s a freeze, 2 s a hang (the watchdog writes `hang-<session>-<n>.json`
  while it lasts, then runs `/usr/bin/sample` on Cra for a second, at most three times a session).
- Stalls are tagged with the run-loop mode. `tracking` (a held menu, a drag), `modal` (an
  alert) and `launch` (from the recorder's start until the run loop first sleeps: AppKit runs
  `applicationDidFinishLaunching` before the loop's first pass) are recorded but are not freezes.
- Breadcrumbs are HitchMonitor's marks (swipes, page shown, extension popups, scripted
  commands), cut before any `?`.

## What is recorded

Main-thread passes as a histogram, stalls with mode, breadcrumbs and the site on screen. Per
process kind (browser, renderer, GPU, utility, other, from Chromium's `--type=` argument): CPU,
memory footprint, disk reads and writes, wakeups (in the file only), and processes started and
ended. The Mac: CPU, memory pressure, thermal state, Low Power Mode, free disk. Tabs by state,
sleep refusals by reason, and timings for tab switch (without the page created for a tab that
had none, which is page create), page create, page load, waking a slept tab and framing an
extension's popup. Long tasks in the visible page. Renderer crashes, hangs and failed loads
with their codes. Start-up phases (store loaded, Chromium started, windows shown, then the
first page shown, committed and loaded), JSON load and save times, the profile's and caches' size (at export).
The session: a random id, the launch number, the previous session and whether it quit.

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

## Measured (2 Nov 2026, M-series Mac)

| | Budget | Measured |
|---|---|---|
| CPU | < 0.1 % of a core | 0.027–0.039 % (`fifty-tabs`, three runs; an idle session 0.027 %) |
| Main thread | < 0.2 ms per tick | ~95 ns per observer callback (114,663 callbacks, 10.8 ms over a `fifty-tabs` run) |
| Memory | < 5 MB | ~5 KB of recorder data (`selfCost.memoryBytes`) |
| Disk writes | < 60 KB per minute | ~5 KB per minute (black box) plus ~4 KB per minute (history) |

`selfCost` in every report says what recording cost that session; `scripts/scenario.sh`
fails a scenario above 0.1 %.

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
4. The `lt` observer in `PageScript.isolatedWorld`, and `setProcessEventHandler` in CraCEF.
5. `perfRecording` and `perfHidesSiteNames` in `AppSettings` (old files keep loading: unknown
   keys are ignored) and their lines in `Fixtures/Model`.
6. The harness lists that compile `Perf.swift` and `CraCore/Perf/*.swift`
   (`Tests/test-browser-manager.sh`, `scripts/test-store.sh`, `scripts/fuzz.sh`), and the
   perf invariant in `scripts/scenario.sh`.
