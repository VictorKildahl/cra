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

## Status

- 13 Nov 2026: decided; CEF 158 not built. Step 1 started.
