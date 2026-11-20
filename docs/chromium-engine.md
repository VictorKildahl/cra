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
- **The hidden Browser's elements**: Chrome's views for a Browser are never seen, so Chrome's element tracker may
  not find them (its `BrowserView`, its toolbar's buttons). Chrome code that `CHECK`s it found one crashes Cra: Clear
  browsing data's Cancel did in 0.1.50 (`cra-browser-element-checks.patch`, scenario `clear-browsing-data-cancel`).
  `apply.sh` runs `engine/chromium/check-element-checks.py` after the patches, so a new Chrome that adds such a
  `CHECK` in `chrome/browser` stops the engine build until it is patched into a null check the same way.
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

## Before the switch ships

What the scenarios can't reach, checked by hand on a release build (`scripts/release.sh`, signed and notarized):

1. **An existing profile on a signed build.** Install the engine build over a CEF Cra with saved passwords and
   signed-in sites: the "Cra Safe Storage" Keychain item opens the same cookies and passwords (no sign-outs, no
   Keychain prompt). `scripts/engine-migration.sh` covers cookies and history on unsigned test copies only.
   Done 15 Nov on a copy of a real profile (signed engine build, no Keychain prompt): 3063 cookies on 1043 sites
   decrypt, the 2 saved passwords stay. The first try found every cookie deleted (below, 15 Nov).
2. **The update itself.** Sparkle from the last CEF release to the engine release: the app relaunches on the
   engine, and the CEF framework is gone from the bundle.
   Done 15 Nov with two Developer ID builds under a test bundle identifier (CEF 0.1.90, engine 0.1.91; LSEnvironment
   kept them on a test data folder and a local appcast signed with the release EdDSA key, their cra:// scheme
   removed): the CEF copy checked in the background, downloaded, installed and relaunched as 0.1.91 within 6 s
   (`launch: automaticUpdate`); the bundle then held Cra Framework.framework and no CEF framework, and its signature
   verified.
3. **A real Intel Mac.** The x64 build starts and loads pages; under Rosetta here its start-up stalled 1.7 s, so
   scenario budgets on Intel are open.
   15 Nov, under Rosetta (no Intel Mac here): the signed x64 build on engine -6 passes 156 of 177 scenarios
   (`CRA_BUDGETS=report`). The other 21 (full screen, Little Windows, menus, PiP placement, the permission card)
   need a live screen: the display slept at 03:18 and the session locked, after which the arm64 build fails the
   same ones. With the screen unlocked all 21 pass on x64 too: 177 of 177 under Rosetta.
   Victor's call, 15 Nov: no real Intel Mac before the release; Intel users report what doesn't work.
4. **Passkeys** with Touch ID (the keychain access group comes from the provisioning profile), and the Web Store
   install flow.
   15 Nov, partly: an engine build with the release profile (`CRA_PROVISIONING_PROFILE`) launches with the shipped
   app's entitlements, and `PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable()` is true on it
   (false on the same build without the profile), so Chrome offers Touch ID passkeys. Creating and using one needs
   a finger. The real Chrome Web Store (past Google's consent page) offers "Add to Chrome" on the engine, with the
   same "Install Chrome" banner it shows CEF Cra.
   Victor's call, 15 Nov: the release ships without a Touch ID passkey made and used on the engine. On his
   profile copy the passkeys in chrome://settings/passkeys are the same as on CEF Cra.
5. **DRM sites**: Netflix and Disney+ open in their WebKit tabs; Spotify plays in Chromium (Widevine).
6. **Speed**: `scripts/perf/rounds.sh` engine against CEF (memory at 20 tabs, tab switch, new tab, start-up),
   results in docs/speed.md.
7. **Daily use on a real profile.** 15 Nov, Victor on -8 with a copy of his data (`CRA_DATA_DIR`, Sync to a scratch
   folder): signed in everywhere, saved passwords fill, extensions and their popups, tab switching, downloads,
   video, audio and calls, and windows, spaces and tabs back after a quit and relaunch. -7 hung at that profile's
   first launch (its download history, fixed in -8). 1Password trusts Cra only at /Applications/Cra.app, so the
   copy needed it added by hand; an installed update keeps that path.

## Status

**15 Nov 2026: merged into main** (engine-158.0.8127.37-8), not yet released. Nothing left before the release but
Victor's call: a real Intel Mac and the Touch ID passkey check are skipped (his call; Intel users report). The numbers the switch made worse (tab
switch, idle CPU, idle wakeups: "Speed, 14 Nov" below) are fixed ("15 Nov, -7"). A CEF build is still
`CRA_ENGINE=cef scripts/build.sh`.

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
  - engine/chromium/patches: 20 of Cra's CEF patches (their CEF hooks now call Cra's layer) and 13 of the
    layer's own (cra-hosted-pages, cra-keys, cra-downloads, cra-download-tabs, cra-permissions,
    cra-fullscreen-status, cra-devtools, cra-content-blocking, cra-page-menu, cra-relaunch, cra-prefs, …).
    fingerprinting-protection is rebased and waits for a full rebuild; spare-pages isn't needed (spares stay out
    of the tab strip); gcm-enabled, extension-trigger-action-null-checks and extensions-normal-windows aren't
    needed on 157. context-menu-embedded-view came late (#466): 0.1.44 and 0.1.45 built page menus and never
    showed them, and only `page-menu-shows` checks that a menu opens (the other menu scenarios run a command
    instead).
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
  `scripts/engine-migration.sh` checks that a Cra on CEF's data folder opens on the engine (its CEF half
  passes; the folder layout is the same, `Chromium/Default`, and so are the Keychain item's names).
  - On 158: the app builds and `scripts/engine-migration.sh` passes both halves (a CEF build's cookie and back
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
  - Quitting: until about 09:30 on 14 Nov most scenarios' quits ran into Chrome 158's Mac shutdown watchdog
    (10 s, then a dump and `RESULT_CODE_HUNG`): the browser waited for the network service to exit
    (`BrowserProcessIOThread::ProcessHostCleanUp`), then for the thread pool (`TaskTracker::CompleteShutdown`).
    Plain Chrome from the same tree quits in 0.1 s, also with Cra's switches and `--remote-debugging-pipe`. Since
    the app stopped acting on page windows the engine doesn't have (focus, find bar, Little Windows, Peek) no quit
    has (45 scenarios); `grep -l "Teardown watchdog" build/scenarios/*/stdout.log` tells if it comes back. The
    watchdog stays on.
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
  - Speed, 14 Nov (scripts/perf/rounds.sh, 3 interleaved rounds, this branch on CEF 156 against the engine on
    158, local bench pages): memory at 20 tabs 784 → 735 MB, settled 795 → 763 MB; new tab to first paint
    103 → 69 ms; tab switch to shown 14 → 21 ms; idle CPU at 1 tab 2.6 → 4.4 %, at 20 tabs 6.0 → 8.6 %; idle
    wakeups at 20 tabs 60 → 116 /s. Per process at idle (top, 1 tab): the browser process 1.3 % against CEF's
    0.3 %, every helper ~0; a 10 s sample of it finds no hot spot (its main thread ~30 busy ms). The slower switch
    is open.
  - Not engine work, found on the way, both fixed: `solid-spaces`'s space-dock reference predated #399 (the open
    emoji cut off and 2 pt off its cell's centre) and #399's EmojiLabel drew nothing in component snapshots (its
    endless text rect); re-recorded with the emoji whole and centred. `unpacked-extension-copy` failed on any
    local test copy while the installed Cra ran: owning the data folder now means no live process holds its
    Chromium `SingletonLock` (DataFolderOwner), not "no other Cra runs"; the Keychain migration and the perf
    recorder keep "no other Cra runs".
  - `page-windows-open-on-cra` (#354) on the engine: pages count as they first show in a Cra window, and Chrome's
    windows for them (a profile's hidden window, a page's DevTools window) start on the Cra window in use without
    macOS's animation (`setPageWindowStartHandler`), as CEF's page windows do. It passes.
  - 14 Nov, end of day: every scenario (170, the six that take over the screen included) passes on the engine,
    on engine-158.0.8127.37-5. Last engine fixes: session cookies outlast a restart (cra-session-cookies.patch,
    session-cookies-relaunch), Safe Browsing's API key, an extension's window over a full-screen Cra joins its
    Space. What remains is the hand checks above (Before the switch ships), then the merge and a release.
  - 15 Nov: a copy of a real CEF profile on a signed engine build lost every cookie at the first launch. Chrome
    158 (`KeychainKeyProviderUserDataDirProtection`, on by default) makes the "v10" Keychain key unavailable
    outside Chrome's own data folder and encrypts with a "v11" key; every value Cra on CEF saved is v10, and a
    cookie that won't decrypt deletes its whole site's cookies. `scripts/engine-migration.sh` had passed on
    the 156 engine and wasn't run again on 158. The bridge turns the feature off (the item is Cra's own, so it
    protects nothing), and `cef-profile-cookies` opens a CEF build's cookie database (Tests/Fixtures/CEFProfile)
    in every run, so it needs no CEF build after the switch. Engine release -6.
  - 15 Nov, on -6: all 177 scenarios pass, the screen ones included. `component-snapshots`' `toolbar-split-pane`
    shot is the pointer's: with the test display (CRA_TEST_SCREEN) unplugged, the window opens under a resting
    pointer and the split pane draws its hover buttons (CEF and the -5 build alike). It passed on 14 Nov with the
    test display connected.
  - 15 Nov, -7: the three numbers the switch made worse, fixed (scripts/perf/bench.sh, 3 interleaved rounds against
    CEF 156). Idle wakeups: a profile's hidden Chrome window (on screen, transparent, so an extension's popup can
    show) kept its compositor drawing and the GPU process's display link ticking; its compositor is hidden now
    (`PageHost::StopDrawing`). Ordering the window out cut as much, but then no popup ever showed, and no scenario
    caught it: `extension-popup-shown` expects the popup Cra frames. Tab switch: Cra's pages draw with
    compositors of their own (they are views in Cra's windows, not Chrome's), which Chrome dropped on every hide
    and made again on every show, a new frame sink before the first frame, a display refresh late; a hidden page
    now keeps it, detached and shrunk to a pixel so the GPU process keeps no buffers of it
    (cra-page-compositor.patch, `tab-switch-first-frame`). Against CEF: idle wakeups at 20 tabs 70 → 42 /s
    (-6: 91), idle CPU at 20 tabs 5.3 → 4.9 % (-6: 5.9), tab switch to shown 11.3 → 11.1 ms (-6: 22.2), memory
    at 20 tabs 779 → 716 MB, back to 1 tab 296 → 271 MB, new tab to first paint 89 → 60 ms. Still above CEF:
    memory at 1 tab 236 → 258 MB (most of it a renderer for the hidden window's blank page) and idle CPU at 1 tab
    2.2 → 2.8 % (the runs' ranges overlap). Every scenario passes (`freezing-live-connection` once failed on
    timing and passed on both reruns); under Rosetta `extension-lifecycle` is over its stall budget on -6 and -7
    alike (first launches of a translated build).
  - 15 Nov, -8: a copy of a real profile hung at its first launch on -7: Chrome makes an item for every download
    in the profile's history as it starts, and the bridge reported each as a download that had just finished, so
    every one ran the download flight. Only a download made in progress is reported now
    (`download-history-quiet`). 1Password's helper refuses any Cra outside /Applications/Cra.app, CEF builds
    too (a test copy needs adding in 1Password ▸ Settings ▸ Browser); not the engine.
  - 16 Nov, -9: the hidden window that holds a profile's pages kept an about:blank tab, and with it a renderer
    process for as long as Cra ran. Its blank page is now a page that never loads, which has no renderer
    (`one-tab-renderers`).
  - 17 Nov, -18 (#484): Chrome hangs an extension's browser-modal dialogs (chrome://extensions' Remove asks
    first) on the current browser window, which is the hidden page host, so Remove did nothing at all. Such a
    dialog now gets no parent and Cra shows it over its own window, as on CEF (`cra-extension-dialogs-parent.patch`,
    `extension-remove`). And Chrome on macOS takes its language from the app bundle's translation folders, which
    Cra's doesn't have, so it ignored `--lang` and stayed English, extensions' chrome.i18n too; it reads `--lang`
    now (`cra-locale.patch`, `chromium-locale`).
  - 17 Nov, -18: a page's DevTools were a window of their own beside the page whose frontend believed itself
    undocked (no close button, no dock menu) and whose keys went to Chrome's hidden DevTools window (⌥⌘I did nothing
    inside DevTools). The frontend now loads dockable while Chrome's window stays undocked, its dock calls come back
    to Cra as on CEF, and its view goes into the card under the page (`cra-devtools.patch`, `EmbeddedDevTools`);
    Chrome's hidden DevTools window never becomes key, which had cost clicks and hover (`devtools-docked`,
    `devtools-docked-clicks`).
- 19–20 Nov 2026, night: **Chrome 159.0.8154.13** (#606), from engine-158.0.8127.37-33. Eight of the 67 patches
  moved with 159's code:
  - same hooks, new context: extension-side-panels (the organizer panel's branches are gone),
    cra-hidden-pages-tabs-query, cra-devtools (the dock CHECK is a DCHECK now, still after Cra's clamp) and
    cra-links (`OpenURLFromTab` builds its pop-up delegate in a helper; dispositions are
    `ui::mojom::WindowOpenDisposition`, with `WindowOpenDisposition` kept as an alias);
  - Chrome did part of the work: 159 turns text input off in `RenderWidgetHostViewMac::SetActive` for any view that
    goes inactive (crbug.com/577708579), which was half of secure-input-active-app (#511), and settings_utils
    goes through `BrowserElements::NotifyEvent`, which returns when the element is missing, which was half of
    cra-browser-element-checks. The other halves stay;
  - ungoogled: the DOM distiller viewer is gone (two fonts.googleapis hunks with it) and the Safe Browsing
    blocking page factory moved to `safe_browsing/interstitials/`.

  Two more things 159 changed that only the build found: the generated `WebSettingsImpl::SetFromStrings` calls a
  `WebSettingsImpl` setter for every setting in settings.json5, so fingerprinting-protection adds one for
  `craFingerprintingSeed`; and the bridge lost two of Chrome's names. `IDS_CONTENT_CONTEXT_SEARCHWEBFORIMAGE`
  ("Search $1 for Image") is gone with its translations, since Chrome labels every image search with the Lens
  string, so `chromiumString(.searchWebForImage)` is the old English template when Chromium runs in English
  (Arc's label stays) and nil in another language (Chrome's own label). `RequestType::kTopLevelStorageAccess` is
  gone; its permission bit goes unused. `check-element-checks.py` and `web-features.py --chromium` found nothing
  new (163 rows, every `WebContentsDelegate` method mapped).

  On 159 (local builds, arm64 and x64) every scenario passes on arm64, the 29 that take the screen too (run in the
  morning: with the screen locked overnight, boost-editor and site-controls-no-extensions failed on 158 and 159
  alike, since no window becomes key). A fingerprinting fixture called the largest audio noise loud on any engine
  (fixed: one float32 step of slack). The web-features gate passes (53 without the screen, 11 with it), `scripts/test.sh` passes, and `scripts/engine-migration.sh`
  with a 158 build as the writer passes (a 158 profile's cookie and back/forward list open on 159). The x64 build
  under Rosetta passes the functional checks of a smoke set (cookies from a CEF profile, downloads, extensions,
  fifty tabs, fingerprinting, live folders); first launches of a translated build go over their stall budgets, as
  on 158.
- 20 Nov 2026: **engine-159.0.8154.13-2**, two crashes from 0.1.50 and 0.1.51's reports. An extension popup's
  Settings that opens the options page as a tab (#626, #631; 52 reports): Chrome closes the popup while the tab
  goes into its tab strip, Cra's window becomes key again, and the bridge's `pageFocused` activated the focused
  page inside that change, which TabStripModel's reentrancy CHECK stops. `pageFocused` now runs once Chrome is
  done, and only for the page focused last: a stale one took the focus back and two pages traded it hundreds of times
  a second (the scenario's stall budget caught it). The view's `HasFocus()` is no test for that, since the window's
  key state reaches it later, and page fullscreen and Little Window fullscreen broke (scenario `extension-popup-opens-options`). A tab closed under its HTTP sign-in prompt (3 reports):
  `CraPageDialogHost` (cra-page-dialogs.patch) is the page's own data, so it told its dialogs it was going only
  after the page's parts were gone, and the prompt's `LoginHandler::CancelAuth` used them. It lets them go in
  `WebContentsDestroyed` now (scenario `page-dialog-sign-in-tab-closed`). Both scenarios crash on -1.
