# Protected media (DRM)

Spotify, Netflix, Disney+ and the other big services open in a WebKit page inside Cra, not a
Chromium one. WebKit plays their DRM with Apple's FairPlay, which macOS gives every app for free.
Everything else stays in Chromium.

## Why

Chromium's Widevine CDM works in Cra: the component updater installs it, and sites whose licence
policy doesn't ask for more play (Shaka's Widevine demo does). The big services ask for more:
**Verified Media Path** (VMP), a signature over the browser's own binaries (`.sig` files next to
the framework and helpers) made with a certificate that Google licenses through paid partners.
Without it:

- Spotify's licence server answers 403/500 and the web player skips track after track.
- Disney+ shows error 83 (GitHub #66).
- Netflix and Max refuse to play, or play in low quality.

Getting VMP costs about €10,000 up front (castLabs: a code audit of Cra's Chromium build, then a
signing service at about a third of that per year), plus a Widevine licence agreement and a
company. Re-signing every release and CEF build would also tie the release pipeline to a
third party.

FairPlay needs none of that. The content provider pays for its FairPlay licence; the browser
only hosts Apple's CDM, which every WKWebView gets. A plain, ad-hoc-signed test app with no
entitlements played EZDRM's public FairPlay stream end to end (certificate, licence request,
licence, keys usable, 720p playing). That is the whole requirement.

## How it works

`ProtectedMediaSites` (CraCore) holds the rules, with tests:

- **Which pages:** the services' web players. Each host matches itself and its subdomains:
  `open.spotify.com`, `netflix.com`, `disneyplus.com`, `max.com`, `hbomax.com`,
  `primevideo.com`, `hulu.com`, `paramountplus.com`, `peacocktv.com`, `tv.apple.com`,
  `music.apple.com`, `listen.tidal.com` and `www.deezer.com`. They are players, not whole domains, except where nothing else signs in through the service (Max sends `play.max.com` on to `www.hbomax.com` and signs in on its own hosts):
  other sites send their "Sign in with Spotify/Tidal/Deezer" through `accounts.spotify.com`,
  `login.tidal.com` and `connect.deezer.com`, and those must finish in the engine they started in.
- **A page Cra opens** (a tab restored or created, a link opened in a new tab, a Little Window, an
  address typed, a pinned tab reset) gets WebKit for a listed site and Chromium for anything else.
- **A Chromium page's own navigation** (a link, a redirect, history) to a listed site is stopped
  before its request goes out. Then the tab's page opens again in WebKit at that address, in the
  same split pane and with the same focus. Stopping it that early means a sign-in callback's
  one-time code is spent where the session will live. A POST stays in Chromium, because its body
  can't move.
- **A WebKit page stays in WebKit** wherever it navigates by itself, because sign-in goes through
  other sites (accounts.google.com, appleid.apple.com) and has to come back to the same cookies.
  Only Cra's own navigation (the URL bar) picks the engine again.
- **A popup** (`window.open`) keeps its opener's engine, so `window.opener` still works for
  sign-in windows.

`WebKitBrowser` (`Sources/Cra/Services/WebKit/`) is a `CraBrowser` subclass backed by a
`WKWebView`. It hosts the way Alloy pages do: its view sits in `containerView`, which split view
places in the pane, and it has no `hostWindow`. It sends the same delegate callbacks as CraCEF.
It also answers the DevTools Protocol methods Cra calls from WebKit's own API:

| Cra calls | WebKit page |
|---|---|
| `Runtime.evaluate`, isolated world | `evaluateJavaScript` / `callAsyncJavaScript` in the page world or in the `cra` content world, answered in the protocol's JSON. Both run as a user gesture. |
| `Page.captureScreenshot` | `takeSnapshot` (tab switcher, Capture); the full page goes through `createPDF` |
| `Page.getLayoutMetrics` | the document's scroll size and the visual viewport |
| `Storage.clearDataForOrigin`, `Network.clearBrowserCache` | the profile's `WKWebsiteDataStore` |
| `Cra.setFreezingVote`, `Cra.load` | accepted; WebKit throttles hidden pages itself |
| `Cra.discard`, `Cra.getFreezingState`, `Target.*` | an error. Tab sleeping then closes the page, and it loads again when shown; extension actions don't apply. |

PageScript's two scripts run in WebKit as user scripts, in the page world and in a `cra`
content world. With them come Cra's typed-text and long-task tracking, the sidebar player's
media session buttons and its volume. A small addition in the `cra` world reports what Chromium
tells CraCEF natively: media playing, Picture in Picture and link hovers (the status bubble).
WebKit's `_isPlayingAudio` drives the speaker when this macOS has it.

Cookies and storage live in WebKit, one persistent `WKWebsiteDataStore` per Cra profile and one
throwaway store per incognito session (`WebKitStores`). The store's identifier comes from the
data folder plus the profile, so a test instance (`CRA_DATA_DIR`) never shares the daily one's.
Deleting a profile deletes its WebKit store at the next launch, together with its Chromium
folder. The user agent is Safari's (`Version/<Safari's version> Safari/605.1.15`), because the
services pick their DRM by browser.

## How Cra tells the user

- **Once per service, a toast that stays**: the first time a service's page shows, "Spotify
  plays with Safari's engine" with a Why? button that opens the Site Control Center. It has no
  timer and stays through Why?. Only its ✕ closes it, so Cra knows it was seen; the ✕ shows its
  round fill only under the pointer. Services whose ✕ was pressed are kept in the
  `protectedMediaToldServices` default. One left open shows again the next session.
- **The Site Control Center**: on a WebKit page, a Protected Media card takes the Extensions
  grid's place. It names the service, says why, and lists what that means here: you sign in once,
  extensions don't run, and Web Inspector opens instead of DevTools. Learn more opens
  crabrowser.app/help/protected-media. The Block Ads & Trackers switch is left out there,
  because Chromium's blocker doesn't see the page.
- **Extension buttons**: pinned extensions in the toolbar, the sidebar's URL field and the
  sidebar's grid dim, and their tooltip says "Extensions don't run on Spotify".

All three follow the page's real engine (`TabNavState.protectedMedia`, from the page), not its
address. A WebKit page signing in on accounts.spotify.com still counts as Spotify's.

## What a WebKit page doesn't have

- **Chrome extensions**, including password managers' autofill: those services are signed into
  once, by hand or from the password manager's own app.
- **Chromium's logins and cookies**: the first visit to a service signs in again.
- **Chromium's site settings, content blocking and HTTPS-Only**: camera and microphone ask
  through Cra's prompt on every visit.
- **Chrome's DevTools**: Develop ▸ Developer Tools opens WebKit's Web Inspector in its own window.
- **Arc's Picture in Picture window**: the video goes to the system's own Picture in Picture
  window, with its controls. Auto Picture in Picture, the sidebar player's button and coming
  back to the tab work as for Chromium pages. WebKit has Picture in Picture off for apps other
  than Safari until its `allowsPictureInPictureMediaPlayback` preference is set (without it,
  `requestPictureInPicture()` answers NotSupportedError).
- **Chromium's fullscreen handling**: WebKit takes a fullscreen video to its own fullscreen
  window, as in Safari, and Esc leaves it. That window covers Cra's, so the covered-window
  auto Picture in Picture leaves a WebKit page in its own fullscreen alone
  (`PageEngines.isInOwnFullscreen`): a request made then got stuck in WebKit's transition, and
  that video never went to Picture in Picture again.
- **In-place tab sleep**: a sleeping WebKit page closes and loads its address again when shown.
  Its back/forward list goes with it.

## Settings

    defaults write dk.kildahl.cra webKitProtectedMedia -bool NO        # every page Chromium's again
    defaults write dk.kildahl.cra webKitProtectedMediaHosts -array crunchyroll.com
    defaults write dk.kildahl.cra webKitProtectedMediaRemovedHosts -array netflix.com

They are read at launch. A test instance takes `CRA_WEBKIT_DRM=0|1` and
`CRA_WEBKIT_HOSTS=<host,host>` (the scenarios list `localhost`).

## Testing

- `swift test --package-path Packages/CraCore --filter ProtectedMedia`: the rules.
- `Tests/test-browser-manager.sh` (`pageEngineCase`): the real `BrowserManager` and
  `PageEngines` choosing engines, popups keeping their opener's engine, and handoffs in both
  directions keeping the split, its order and its focus.
- `scripts/scenario.sh webkit-drm-tabs`: the running app. The fixture server is reached as
  `localhost`, which the run lists, so it needs no network and no account. The scenario covers
  FairPlay being offered and every emulated protocol method. It also covers both handoffs, split
  view with one engine per pane, the sidebar player and its media-session buttons, playback
  while the tab is out of sight, a Little Window, tab sleep, waking and closing.
- On screen (4 Nov 2026, a renamed test copy): a WebKit tab and a split with one engine per
  pane drawn in their cards. Picture in Picture opens from the player's button, on leaving the
  tab, and after container and video fullscreen. Fullscreen enters and Esc leaves. ⌘F opens Cra's
  find bar with a count, and ⌘L opens the command bar with the page's address. In a background
  instance, EZDRM's public FairPlay stream played (licence, keys usable, 720p), and logged out,
  Spotify, Netflix, Disney+, Max, Apple TV, Apple Music, Prime Video and Tidal open in WebKit with
  no "browser not supported" message. Cookies and storage survive a relaunch, which restores the
  tab in WebKit. A download from a WebKit page lands in Downloads.
- Still by hand, with real accounts: Spotify plays track after track, Netflix and Disney+ play,
  and sign-in through Google or Apple comes back signed in. Peek from a pinned WebKit tab.
