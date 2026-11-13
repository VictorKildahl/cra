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
| Page processes | ~33 MB each | ~26.5 MB each | Not the engine: a dirty copy of the framework's `__DATA_CONST` (12.4 MB) in every Cra helper, fixed 13 Nov (below: ~20 MB each now). |
| Browser process | ~210 MB | ~155 MB | CEF makes every tab a Chrome browser with its own (hidden) window and toolbar. |
| GPU | ~160 MB | (with network, storage, its blocker: ~250 MB) | Even now that five hidden tabs keep their frame. |

For scale, Google Chrome 157 on the same steps (13 Nov 2026, `chromium-bench`-style CDP run with its own
profile): 417 MB at 1 tab, 827 at 10, ~1,200 at 20, 396 back at one. Cra (~309 / ~805 / ~1,150 / ~370) is
already below stock Chrome; the other browser's lower numbers come with a base that strips Chrome's
Google services as well as its newer engine and no CEF.

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

## Done the night after (12–13 Nov 2026)

- **Spare pages** (`SparePages`, `spare-pages.patch`): a page per profile made ahead; a new tab, a link
  opened in a tab and the first visit to a restored tab take it. Page making 34 → 21 ms on average
  (15 of 26 pages from a spare at a click every 1–2 s), switch to a restored tab's page shown 30 → 12 ms,
  opening a site 36 → 16 ms. Extensions never see a spare (`spare-pages.scenario`).
- **Tabs switch on the press**, as Arc 1.173.1 does (checked live): the click's own length, ~90 ms,
  comes off every sidebar switch. Picks, renames and a pinned tab's icon act on the release.
- **Space switches** no longer ask the window server which window is under the pointer every frame of
  the spring (207 ms of the main thread over six switches).
- **Updates**: the warm-up runs the five helper apps too; a fresh copy's first launch 3.5 → 0.6 s.

What is left on a switch is Chromium's own work on the browser side as pages load (Chrome pays it too)
and ~8 ms of Cra's refresh per switch.

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

### 2. A newer Chromium

13 Nov 2026: CEF has a 158 branch (8127, Chromium 158.0.8127.18, 10 Nov), still a beta engine; Cra takes
stable CEF only (check-cef-update.sh, the release gate), so it waits for Chrome 158 stable unless Victor
decides otherwise. Building it needs ~80 GB beside the 156 checkout (44 GB free that day; the plain
Chromium output in out/Chrome_arm64, 12 GB, can go first).

CEF skipped 157: its master went from 156 to 158 (158.0.8127.0, 4 Nov 2026) and only 156 has a
release branch (8078). The daily CEF update check opens the issue when a stable 158 branch exists;
take it with `scripts/update-cef.sh` as soon as it does, and measure the page processes against 156.
Every engine round also needs the Intel build ([release.md](release.md)).

### Measured before deciding on 3: plain Chromium from the same tree (13 Nov 2026)

Chromium 156 built from the CEF checkout itself (`out/Chrome_arm64`: CEF's GN args plus
`enable_cef=false`; `scripts/perf/plain-chromium.patch` guards the seven places where CEF's patches use
CEF code unguarded; a stub `third_party/widevine/scripts/signature_generator.py` that writes an empty
signature, since that signer isn't in the checkout; ~4 h on the M2 Max at low priority) and run through
the same steps over CDP:

| 20 tabs, settled | Cra (CEF) | Plain Chromium 156 |
|---|---|---|
| Total | ~1,150–1,200 MB | 1,286 MB |
| Browser process | ~210 MB | 113 MB |
| GPU and other helpers | ~280 MB | 435 MB |
| Page processes | ~33.6 MB each | ~37 MB each |

On the same engine, Chromium without CEF uses more memory here than Cra does. CEF's cost per tab in the
browser process (~100 MB at 20 tabs) is real, and Chrome's own GPU and helper processes spend more than
that. So leaving CEF would not by itself bring Cra to the ~930 MB of the browser above; that one strips
Chrome's background services (its Helium-style base) and runs a newer engine. Before 3, the cheaper
lever is the same as theirs: turn off Chrome background features Cra doesn't use, one at a time,
measured with `scripts/perf/rounds.sh`.

Started 13 Nov 2026: OptimizationHints, PreloadingHeuristicsMLModel, HistoryEmbeddings, Glic and LensOverlay
off (Google services Cra never offers): 11–12 MB less in the browser process at 20 tabs, two rounds of
`MODES=procs` with `BENCH_ARGS`. Feature switches don't move a page process's own size; how the
framework is loaded does (next section).

### Done 13 Nov 2026: the framework is linked at launch (~14 MB less in every helper process)

A page process's 33 MB held 12.4 MB of the framework's `__DATA_CONST` as a private, dirty copy, and so
did the GPU process, every utility process and the browser process. Google Chrome's helpers have the
same 12 MB region clean (shared with the file). The difference was how the framework gets loaded, not
the engine: Chrome's helpers name their framework as a launch-time dependency, so dyld maps it before
libSystem is up and the kernel binds its pointers page by page as they are read (page-in linking). Cra's
helper (and our own plain Chromium 156, which loads its framework with dlopen too) mapped it later
with `CefScopedLibraryLoader`, after launch, where dyld binds every pointer itself and writes the whole
region. Ruled out on the way: signing (Developer ID with Chrome's flags), the sandbox, the SDK, the
pointer format.

Now `CraHelper` links `Sources/CraHelper/ChromiumEmbeddedFramework.tbd` (the framework's path as a
helper sees it) and `Cra` links the framework itself; the dlopen that follows gets the same image.
The seatbelt still goes on before any CEF code runs: mapping runs only the framework's 10 static
initializers (C++ globals, no I/O), and every helper reports sandboxed. `scripts/build.sh` fails when
the helper stops linking the framework or the path doesn't resolve.

Measured on a 0.1.42 copy with only the helper changed, two interleaved rounds, 20 bench tabs:

| | Before | After |
|---|---|---|
| Page process | 34–35 MB | 20–21 MB |
| Page processes, 20 tabs | ~700 MB | ~410 MB |
| Total, 20 tabs settled | 1,072–1,103 MB | 817–848 MB |
| Total, 1 tab | 248–293 MB | 220–223 MB |

That puts Cra's page processes below Chrome 157's and below the other browser's (~26.5 MB).

### Done 13 Nov 2026: hidden tabs' frames go 2 s after a switch, a few windows at a time

The GPU process held ~370 MB for up to a minute after twenty tabs were opened: the hidden tabs past
Chromium's five saved frames were only released (HiddenFrameRelease) on the once-a-minute tab
cleanup pass. The release now also runs 2 s after the page windows last changed
(`HiddenFrameRelease.afterPageChange`). 20 bench tabs, `MODES=procs`, 20 s after the last one:
GPU 371 → 148 MB, total ~1,000 → ~790 MB.

Each window that draws for a release goes in as a child of the browser window, and AppKit sorts all
of that window's children on every order in and out: with fifty tabs opened quickly, 45 windows at
once held the main thread 2.3–3.2 s (the minute pass did the same, at a random moment). It now draws
`perPass` (4) at a time, a pass every 0.65 s: fifty-tabs' longest stall 2,265 → ~120 ms.

Five more Google services off (SegmentationPlatform, PageInfoAboutThisSite, AutofillServerCommunication,
VisitedURLRankingService, ModelQualityLogging) measured no change in the browser process (199–205 MB
with and without, two interleaved rounds), so they stay on.

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
