# Chromium engine: Cra on Chrome's own framework, without CEF

Decided 13 Nov 2026. Cra moves from CEF to Chrome's own `//chrome:chrome_framework` with a thin layer of Cra's own
code linked in. The Swift app and CraCore don't change: the layer is a second implementation of the bridge in
`Sources/CraCEF/include/CraCEF.h`, in its own app build, and Cra switches over in one go once it does everything the
CEF one does.

## Why

- **Memory.** CEF makes every tab a Chrome browser with its own hidden window: ~4 MB a tab in the browser process
  (docs/speed.md, "Looked at 13 Nov 2026"). Chromium 156 from the same tree, 20 tabs in one window: 113 MB in the
  browser process against Cra's ~210 MB.
- **Engine version and security fixes.** CEF skipped Chromium 157, so Cra stayed on 156 and its extended-stable
  fixes. On Chrome's framework Cra builds any Chrome stable tag the day it ships.
- **Same cost to build.** Cra already builds Chromium for its codecs (scripts/build-cef.sh): ~2.5–4 h a CPU for a
  full build, ~2 h for a new tag, ~45 GB for the checkout and one output per CPU.

## Shape

- **One Chrome `Browser` per Cra window**, normal type, with Chrome's own (hidden) window: its tab strip holds the
  window's pages, so `chrome.tabs`, popups, extension popups, permission prompts, autofill and passkeys keep working
  as they do in Chrome. Cra shows each page's view in its own window (as EmbeddedPages does today) and tells
  Chromium which pages are on screen (split panes, Peek and Little Windows show more than the active tab).
- **The layer** (`engine/chromium/cra/`, copied into the tree as `//cra`): a `ChromeMainDelegate` and
  `ChromeContentBrowserClient` of Cra's own, the bridge's Objective-C classes, exported from the framework.
  `chrome/app/chrome_main.cc` takes Cra's delegate through one hook.
- **Patches** (`engine/chromium/patches/`): the ones in `scripts/cef-patches` that change Chrome's own code come
  along (extensions, fingerprinting, translate, keychain, freezing, live connections, spare pages, ...); the ones that
  fix CEF become the layer's own code. Google's background services go with ungoogled-chromium's patches (BSD,
  taken one by one); never Helium's (GPL-3.0; Cra is MIT). Chrome's security updaters stay on: CRLSet, PKI
  metadata, Safe Browsing lists.
- **CPUs**: arm64 and x64, as every release (docs/release.md).

## Steps

1. **Test build** in the CEF tree (Chromium 156.0.8078.96, `out/Chrome_arm64`, built 13 Nov with
   `scripts/perf/plain-chromium.patch`): a bare AppKit app on Chrome's framework and the layer that loads a page in
   two profiles, takes a popup as its own tab, shows an extension popup, and quits cleanly. Go or no-go.
2. **Engine tree** on Chrome 157.0.8103.81 (or the newest stable then): Cra's patches ported, ungoogled-chromium's
   service patches, codecs, official build with PGO. `scripts/build-chromium.sh`, publish like `publish-cef.sh`.
3. **The bridge**, method by method, in the order the scenarios need them: page lifecycle and navigation, popups and
   new tabs, keys and focus, downloads, permissions, DevTools, find, Picture in Picture, extensions, spare pages,
   agent pages, profiles and incognito, prefs and secure DNS, the browser DevTools pipe.
4. **Switch**: `scripts/test.sh`, every scenario and `Tests/promises.lock` on the new build, then `scripts/perf`
   against the CEF build, then the release.

## Start-up (step 3's first piece)

CEF let Cra drive Chromium: `CraCEFRuntime.initialize…` started it and `runMessageLoop` ran the loop. In Chrome's
framework `ChromeMain` owns the whole run, start to quit. So:

- `Sources/Cra/App/main.swift` keeps its order. The part after `initialize…` (Chromium's handlers, the perf
  recorder, `bootstrapIfNeeded`) moves into a block the bridge runs once Chromium is ready, and `runMessageLoop`
  becomes `CraEngineMain`, which returns at quit; the CEF bridge runs the same block at once, so both engines take
  the same main.swift.
- `CraApplication` subclasses Chrome's `BrowserCrApplication` and exists before `ChromeMain`, so Chrome uses it.
- Chrome's `AppController` (NSApp's delegate) and main menu must not replace Cra's `AppDelegate` and menus: a hook
  in `ChromeBrowserMainPartsMac` skips them when Cra's parts are present.
- The bridge's Objective-C classes live in the framework (`//cra`), exported in `framework.exports`; the SwiftPM
  `CraCEF` target keeps `include/CraCEF.h` and, for this engine, only links Chrome's framework.

## Waiting on the bridge

Fixes that need a signal CEF doesn't give Cra. Each is part of switching over, with its test.

- **The sidebar player follows the media session (#411's follow-up), done on this branch 13 Nov 2026.** Arc's
  card holds the media session's status. The layer's `MediaSessionWatch` sends Chromium's `MediaSessionInfo`
  state and `is_controllable` (`browser:didChangeMediaSessionState:controllable:`, `reportsMediaSession` YES),
  and CraCore's `PlayerCardSession` decides:
  - a controllable active session makes the card and plays it;
  - suspended shows it paused, however long;
  - a controllable session going inactive (Chromium removes an ended player from the session) removes the card
    2.5 s later, Chrome's `kFreezeTimerDelay`, and a next track within the wait calls that off;
  - anything uncontrollable leaves the card as it is. Chromium resets a paused session when a ding starts
    (`MediaSessionImpl::AddPlayer` clears its players), so the inactive state after a ding never removes a
    paused card.

  On CEF and on WebKit pages the player still follows the audible state. Tests, locked to #411:
  `PlayerCardSessionTests`, the harness's `nowPlayingFollowsMediaSessionCase` and the scenario
  `player-follows-session`, which runs only on the new engine (on CEF the ended card stays).
  Known difference from a plain reading of the issue: a page whose media session sets `playbackState`
  (YouTube) stays controllable through a ding, so its paused card shows playing during the ding, as Chrome's
  own media controls do.

## Status

- 13 Nov 2026: decided; CEF 158 not built.
- 13 Nov 2026, step 1 done, **go**. `engine/spike.sh` on Chromium 156.0.8078.96 (`out/Chrome_arm64`, the CEF tree with
  `scripts/perf/plain-chromium.patch` and `engine/chromium/apply.sh`): all 12 checks pass. Cra's code runs in Chrome's
  browser process; two profiles keep their storage apart; pages of two Browsers show in Cra's window at once and
  stay there; a popup arrives as a tab of its opener's Browser with `window.opener`; an extension's popup opens
  from a Browser whose Chrome window was never shown; Chrome's own exit quits with code 0; the app never took
  the focus. 20 tabs of scripts/perf's bench page, measured as `MODES=procs` measures Cra:

  | | Cra on CEF | Test build |
  |---|---|---|
  | Total | ~790–830 MB | 706 MB (two processes more: the second profile's page, the extension) |
  | Browser process | ~185–200 MB | 102 MB |
  | GPU | ~117–148 MB | 96 MB |
  | Each page | ~20 MB | ~20 MB |

  Learned:
  - **Aperitif helpers.** Chrome has two sets of helper apps; only the "Aperitif" ones link the framework at
    launch (its `__DATA_CONST` clean, as Cra's CraHelper does since 13 Nov). They're behind `AperitifHelpers`,
    off by default in 156 (Chrome turns it on by field trial): without it each page was 28 MB. The layer has to
    turn it on.
  - **An extension's popup shows its Browser's Chrome window** (1200×1366 here). Cra on CEF has the same window
    and keeps it out of sight; the layer will do the same.
  - The hooks are inert for CEF: the CEF build doesn't build `chrome_dll`, and `cra::g_extra_parts_factory` is
    only set by `CraEngineMain`.
- 13 Nov 2026, step 2's first build: Chrome 157.0.8103.81 from `scripts/build-chromium.sh` (official, ThinLTO + PGO,
  codecs; `~/chromium.noindex`, 3.5 h with other builds on the Mac). The layer built on 157 unchanged, and
  `engine/spike.sh` passes all 12 checks again. 20 tabs of the bench page: total 702 MB, browser process 101 MB,
  GPU 111 MB, pages 16 MB each (median), the framework's `__DATA_CONST` clean in the pages. Cra's patches and
  ungoogled-chromium's service patches are not in yet.
- 13 Nov 2026, step 3 started: **Cra's own app runs on Chrome's framework.** `CRA_ENGINE=chromium scripts/build.sh`
  builds `build/engine/Cra.app` (its own bundle id and executable, CraEngine, so it never meets an installed
  Cra) with the bridge, `engine/chromium/cra/bridge.mm`, inside Chrome's framework; `CRA_APP=… scripts/scenario.sh`
  runs scenarios on it. A framework relink after a change to the layer takes ~2 min.
  - Start-up: Cra makes NSApp (`CraApplication`, a `BrowserCrApplication`), its delegate and menus, then
    `runMessageLoop` runs `ChromeMain`; `+[CraCEFRuntime whenReady:]` runs main.swift's after-start part in
    `PostBrowserStart`. Chrome skips its AppController and main menu (`cra::g_embedder_owns_app`), the bridge holds
    the keep-alive AppController would, and quitting is Chrome's `CloseAllBrowsersAndQuit`.
  - Pages: a hidden Browser per profile holds them as background tabs behind a blank active one, so Chrome never
    takes a page's view; Cra shows `containerView` (the embedded-page path, `chromeHosting` NO). Load, address,
    title, loading, progress, back/forward, failures, sound, focus, popups (adopted through the opener's
    `popupHostForURL`) and close work; everything else answers "not yet".
  - Scenarios passing: fifty-tabs, restore-windows-off, library-width, solid-spaces. Failing: start-on-new-tab (the
    command bar stays open in a background test copy: CEF's page focus takes key from the non-activating panel,
    a plain `makeKeyWindow` doesn't in an inactive app), sleep-tabs (tab sleep not in the bridge yet).
  - Next: the methods the scenarios need, in the order of step 3; extensions see a blank active tab until Cra's
    selected page is Chrome's active tab without Chrome taking its view.
- 13 Nov 2026, evening: the bridge covers most of CraCEF.h. On top of start-up and pages: each page's DevTools
  protocol session with Cra.* (freezing, discard, history, translate, automatic PiP, spare, side panel), the
  browser DevTools pipe, the CEF bridge's switches and features, keys (Cra's shortcuts before and after the page,
  never Chrome's), favicons, theme and background colours, find, zoom, SSL status, element fullscreen and the
  link status line, prefs (HTTPS-only, fingerprinting, appearance, secure DNS, any pref as JSON), downloads
  (Cra's destination, progress, pause/resume/cancel), permission prompts (Cra's card), DevTools (Chrome's
  DevTools window hidden, its frontend docked in Cra's card), Picture in Picture and print, blocked pop-ups and the
  site's pop-up setting, ad and tracker blocking, the camera/microphone indicator, process events, browser
  fetches with a profile's cookies, Arc's page menu, document start scripts, restored history, spare and side
  panel pages, extension tabs and windows, stray windows, a second launch's URLs.
  - engine/chromium/patches: 19 of Cra's CEF patches (their CEF hooks now call Cra's layer) and 13 of the
    layer's own (cra-hosted-pages, cra-keys, cra-downloads, cra-download-tabs, cra-permissions,
    cra-fullscreen-status, cra-devtools, cra-content-blocking, cra-page-menu, cra-relaunch, cra-prefs, …).
    fingerprinting-protection is rebased and waits for a full rebuild; spare-pages isn't needed (spares stay out
    of the tab strip); gcm-enabled, extension-trigger-action-null-checks and extensions-normal-windows aren't
    needed on 157.
  - Scenarios passing on the new engine: fifty-tabs, sleep-tabs, cookie-banners, restore-windows-off,
    library-width, solid-spaces, dev-mode, developer-bar, find-selection, app-shortcuts, devtools-close-tab,
    permission-card, download-actions, app-icon-download. Not yet: start-on-new-tab (background command bar),
    blocked-popups (fix in, not rerun). The whole suite runs whenever the Mac is idle.
  - Still to do: Cra.mediaSession and Cra.installFromWebStore, agent pages and agent downloads, extension
    popups (Chrome's hidden window still shows for one), runChromeCommand, ungoogled-chromium's service patches,
    the Intel build, then step 4.
- 13–14 Nov 2026, night: **Chrome 158.0.8127.37**, the Mac stable `scripts/check-engine-update.sh` reported. The
  sync now fetches only the new tag, one commit deep (gclient's `--with_tags` fetched every tag into the shallow
  checkout and never finished). Seven patches moved with 158's code (blocked-popups, page-activate,
  extension-popup-no-popout-wait, cra-permissions, fingerprinting-protection's OfflineAudioContext part, and
  ungoogled's avatar and intranet-redirect patches); the layer needed one change (Document Picture in Picture is
  `TYPE_FLOATING`). The sidebar player follows the media session (#411's follow-up, above), and
  `scripts/test-engine-migration.sh` checks that a Cra on CEF's data folder opens on the engine (its CEF half
  passes; the folder layout is the same, `Chromium/Default`, and so are the Keychain item's names).
  - On 158: the app builds and `scripts/test-engine-migration.sh` passes both halves (a CEF build's cookie and back
    and forward list open on the engine).
  - Audio scenarios (player-follows-session, player-skips-dings, music-notes) couldn't be judged overnight: with
    the displays asleep, this Mac's audio output stalled after the first render quantum for the CEF build as well
    (an AudioContext stayed at 5 ms, a playing `<audio>` at 0.064 s). They run again with the Mac in use.
  - Links Cra opens its own way were missing on the engine (the suite's boost-install found it):
    `+setAppLinkHandler:` did nothing and nothing asked Cra before Chrome opened a link. patches/cra-links.patch
    adds four hooks:
    - `g_link_open`, from `AddNewContents` and `OpenURLFromTab`: another app's address, a Little Window (⌥⌘), a
      split pane, a Peek, in OnBeforePopup's order;
    - `g_external_protocol`, from `HandleExternalProtocol`: cra-boost: and other apps' links ask in Cra, and
      cra: is refused;
    - `g_navigation_throttles`: a same-tab link that opens in a Peek, pages Cra hands to WebKit;
    - `g_download_intercept`, from `InterceptDownloadIfApplicable`: an Option-clicked link opens in Split View
      (#298).

    Click modifiers come from `-[CraApplication sendEvent:]`, as on CEF, and `browser:didChangeSoundPlaying:`
    from the page's audio players.
  - Quitting: Chrome waits up to 10 s for the network service to exit at shutdown
    (`BrowserProcessIOThread::ProcessHostCleanUp`), and under Cra it stays up for all of them, on CEF too (a
    relaunch's "Cra quits" to the next start: 11.6 s). On 158 the thread pool's shutdown then waits too
    (`TaskTracker::CompleteShutdown`, every worker idle), so without Chrome 158's new Mac shutdown watchdog a
    quit took over 30 s; the watchdog ends it at 10 s with a dump and `RESULT_CODE_HUNG`, and stays on. Why
    the network service stays up and what the thread pool waits for are open.
  - The engine has no Chrome window per page (CEF's Chrome-style hosting has one over each card), so app code
    that read a page's place from `hostWindow` did nothing on it. `TabRuntime.pageWindow`, `pageScreenFrame` and
    `pageViews` fall back to the page's view; Peek, 5-Second Previews, page focus, the find bar, Little Windows
    (DevTools beside the page: `DevToolsPlaceholder.besidePage`) and extension side panels use them. Captures,
    probes, the focus ring and hidden-frame release already fell back to the view or are CEF's only.
  - Chrome's bars over a page ("<extension> started debugging this browser", #241) show in its hidden window on
    the engine: the bridge reports Chrome's yes/no bars (`infoBars`, `browser:didChangeInfoBars:`) and the card
    draws them (`InfoBarStrip`, `PageInfoBar` in CraCore) above the page.
  - A page's own pop-up (window.open with features) is a Cra tab, as on CEF (cra-links.patch), not a pop-up
    window of Chrome's.
  - DevTools report the panel they show (`devToolsShowsPanel`, for ⌥⌘J and Network, #138) from the same frontend
    script as on CEF. `devToolsPageBounds` stays CEF's: the engine's frontend is a window of its own, never docked
    over the page, and Cra puts it beside the page.
