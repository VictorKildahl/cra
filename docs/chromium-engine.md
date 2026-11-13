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
