# Web features

What a page asks its browser for (a file picker, print preview, a dialog, a permission, a device chooser, full
screen, a share sheet) and the tests that keep each one working. Chromium's own tests can't do this for Cra:
they run Chrome's own windows, and what breaks in Cra is the seam between Chrome's code and Cra's windows.

## Why Cra needs its own

On the engine (docs/chromium-engine.md) every page belongs to a Chrome `Browser` whose window is never seen.
Since 0.1.49 (#346) that window is a 1 pt strip along the top of Cra's window. Cra shows the page in its own
window. Chrome's code for what a page asks often reads that `Browser` window, and gets the wrong answer:

| What broke | What Chrome read | Fixed |
|---|---|---|
| Every upload button did nothing (#571) | the window's size (`WebContentsBasedCanceller::IsWindowTooSmall`: 400 × 300 at least) | engine -26, `cra-file-picker-window.patch` |
| Print preview 1000 × 3 pt (#574) | the window's size (`GetMaximumDialogSize`) | engine -27, `cra-page-dialogs.patch` |
| A split's right-pane alert over the left pane (#574) | the window's middle | engine -27, `cra-page-dialogs.patch` |
| Every `PaymentRequest.show()` turned down as from a background tab | whether the window is active (never) | `cra-payments-window.patch` |
| No "Page Unresponsive" for a hung page, ever | any DevTools session on the page (Cra's page scripts keep one on every page) | `cra-page-hang.patch` |
| `chrome.action.openPopup()` always failed ("inactive window") | whether the window is active (never) | `cra-extension-popup-window.patch` |
| Chrome's pointer-lock bubble at the top of Cra's window, none for a page's full screen (Arc: its toasts only) | the window's bubble; full screen is Cra's | Arc's toast: the pointer's from `cra-exclusive-access-notice.patch` (Chrome's bubble gets NONE), full screen's from Cra's own |
| The Cast dialog (View ▸ Cast…, the page menu's Cast…) at the window's top left, over the sidebar; a page's `PresentationRequest.start()` got Chrome 159's media controls dialog, not Arc's Cast dialog | the Browser's top container, in the strip | `cra-cast-dialog.patch`: Chrome's own placement for a page without a Browser, centred on the page's top edge, and the Cast dialog for a page's request, as in Arc |
| Closing a tab signed Discord out (#705): it writes its token back on `beforeunload`, and takes it out while it thinks DevTools are open (`outerWidth - innerWidth` > 160, which Cra's sidebar is) | nothing: Cra's close deleted the page without running its `beforeunload` or unload | engine -21, `cra-close-without-asking.patch`: Chrome's own tab close, its "Leave site?" answered Leave without showing, as Arc never asks |

Chromium's own suites (`browser_tests`, `interactive_ui_tests`) and other browsers' tests (CEF's `ceftests`,
Electron's specs, Brave's filtered upstream suites, Web Platform Tests) were looked at on 19 Nov 2026. None would
have caught these: they run Chrome's own visible window, or stub the native dialog, or skip the UI
(WebDriver sets a file input's files without a picker).

## The map

`Tests/web-features.tsv` lists every way a page reaches its browser:

- each method of `content::WebContentsDelegate` (`delegate` rows), Chrome's interface for what a page asks of
  the window that holds it;
- the features Chrome serves outside it (`feature` rows): permission prompts, choosers, passkeys, payments,
  sharing, sign-in, translate.

Each row is tested by `scenarios a,b`, by a `checklist` line in docs/release-checklist.md (`web feature: <name>`:
macOS's own prompts or a real site), or says why a page can't reach it on a Mac (`n/a: <why>`: Android only,
installed web apps only, no UI).

`scripts/web-features.py` checks it:

- `scripts/test.sh`: every scenario named exists, every checklist row has its line (and Tests/test_web_features.py
  tests the checker).
- `scripts/build-chromium.sh` and `scripts/publish-engine.sh`, with `--chromium <src>`: every
  `WebContentsDelegate` method of that Chrome is in the map, and none Chrome dropped is. A new Chrome's new page
  hook stops the engine until someone finds what a page does to reach it and adds its row with a test.

## The gates

- **Every release** (`scripts/release.sh`): `scripts/scenario.sh web-features` runs every scenario the map names,
  and those in `Tests/release-gate.tsv` (what a release once shipped broken outside the map: DevTools after
  0.1.44, a profile switch on 0.1.45, a page's new tab, Extensions' Remove…; a row per issue, added once its fix is
  locked), on a copy of the release's own build (this Mac's CPU), in the background while Apple notarizes. One failure
  stops the release. The result goes into the release as `web-features-arm64.txt`.
  `CRA_SKIP_WEB_FEATURES="<why>"` releases without it; the notes say why.
- **Stable** (`scripts/promote.sh`): only a release whose `web-features-arm64.txt` says `result: passed`.
  `CRA_PROMOTE_UNTESTED="<why>"` for a release from before the check.
- **Nightly**: every scenario, these among them, the screen ones too.

`scripts/scenario.sh web-features` runs the scenarios that need no screen three at a time (`CRA_LANES`), then the
screen ones one by one (`CRA_SCENARIO_SCREEN=1`); without it they're listed as skipped.
`build/scenarios/web-features.txt` says how it went.

## Adding a feature or changing the seam

- A change to how Cra hosts pages (the host strip, `bridge.mm`'s page views, focus, the active tab) runs
  `scripts/scenario.sh web-features` before it ships. #346 changed the strip and broke uploads and print.
- A new web feature Cra handles itself, or a new Chrome feature with UI: a row in the map, a scenario (the
  `cra://debug` readouts below), and the fixture in `Tests/Fixtures/Pages/features.html`.
- A page hook that only needs the right window to read (the bug class above): fix it in the engine for Cra's
  pages only (`cra::kCraPageHostWindow`, `cra::g_page_window_active`), not by changing what Chrome's whole
  `Browser` reports. Many callers depend on that.

## Readouts

- `cra://debug?pageDialogs=<label>[&press=<button>][&fill=a,b]`: every window Chrome shows for a page
  (dialogs, bubbles, popups, the colour panel, the share popover), where it sits against the page (CraCore
  `PageDialogPlacement`: `page`, `window`, `sliver`, `off`), its text and buttons; presses and fills.
- `cra://debug?permissionCard=<button>`: Cra's permission card and its answer.
- `cra://debug?windowState=<label>`: sheets (`sheet=1`: the file pickers) and full screen.
- `cra://debug?chromeWindows=<label>`: Chrome's own windows, the host strip among them.
- `cra://debug?appWindows=<label>`: every window of Cra's on screen, for a feature no other readout knows.

## Known, not fixed here

Other Chrome code asks whether the `Browser` window is active and always hears no. `GlobalBrowserCollection::
GetActiveBrowser()` is always empty: autofill's Google Pay card bubbles (virtual card enrollment, offers, a filled
card's details) never show, and tab discarding has no "focused tab". Making the hidden window report Cra's
window's state everywhere would also wake Chrome's own toolbar bubbles (downloads, translate) anchored to that
never-seen strip, so only the callers that matter get Cra's answer (`cra::g_page_window_active`): payments,
`chrome.action.openPopup()`. The share picker opens at the pointer, as in Chrome, which can be beside the page.

## Notices (Arc 1.173.1, measured 19 Nov 2026)

Chrome decides the notice for a page's locks and hands it over (`cra-exclusive-access-notice.patch`); a page's
full screen is Cra's own (`cra-fullscreen-status.patch`), so Cra says that one itself as it takes the window full
screen. Either way it is Arc's toast (CraCore `ExclusiveAccessNotice`): "To exit full screen, press ⎋." in a browser window (none in a Little Window, as in
Little Arc), "Your cursor is hidden. Press 'esc' to show cursor." for a pointer lock. Under a page's keyboard lock
Arc shows the same full-screen toast; a press of Esc is the page's and Arc offers the next ("[⎋] again to exit
fullscreen"), which leaves full screen (`KeyboardLockEscape`). Arc's toast has "Edit the shortcut" there; Cra's Esc
isn't a shortcut you can change, so it has no button.
