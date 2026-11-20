# Protected media (DRM)

Spotify, Netflix, Disney+ and the other big services open in a WebKit page inside Cra, not a
Chromium one. WebKit plays their DRM with Apple's FairPlay, which macOS gives every app for free.
Everything else stays in Chromium.

## Confirmed playing

- **Disney+**, signed in, on Cra 0.1.31: confirmed by a user in
  [#66](https://github.com/VictorKildahl/cra/issues/66#issuecomment-6660281915) ("it works
  perfectly"), the issue that reported Disney+'s error 83 in Chromium.
- **Prime Video**, signed in, on Cra 0.1.31: confirmed by another user in
  [#66](https://github.com/VictorKildahl/cra/issues/66#issuecomment-6666097911).
- **EZDRM's public FairPlay stream**: plays end to end (certificate, licence, keys, 720p video).

It isn't only a fixed list of sites. Any other site that asks for Widevine gets a **Safari's
Engine** switch in its Site Control Center, and with it on the site plays in WebKit from then on
(see [How it works](#how-it-works)).

A third kind is the site that is mostly not DRM: YouTube, where a film bought or rented plays at
480p in Cra's Chromium among ordinary videos that play fine. There Cra asks, and moves only the
page that plays the film (see [Protected videos on an ordinary site](#protected-videos-on-an-ordinary-site)).
That YouTube gives Safari's engine more than 480p for a purchase has not been checked with a real
account yet.

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
  `music.apple.com`, `listen.tidal.com`, `www.deezer.com`, `crunchyroll.com`, `hotstar.com`,
  `jiohotstar.com` and `v.qq.com`. The last four come from Ardia, another open-source browser that
  sends DRM sites to WebKit (its `PROTECTED_VIDEO_SITES`). Joyn (`joyn.de`, `.at`, `.ch`) and Rakuten TV
  (`rakuten.tv`) were seen refusing non-VMP Chromium with "Verified Media Path" errors; SkyShowtime,
  NOW (`nowtv.com`), WOW (`wowtv.de`) and Showmax run on Sky's and Peacock's platforms, which fail
  the same way. Zattoo, Movistar Plus+, Crave, RTL+ and Viaplay had weaker evidence and are left to
  the switch below. Amazon has path entries: Prime Video at
  `amazon.<store>/gp/video` (the US and Amazon's other stores that serve it there), and Amazon Music at
  `music.amazon.<store>`. The rest of Amazon (shopping, Login with Amazon) stays in Chromium.
- **Any other site, by the user**: when a Chromium page asks for Widevine (PageScript's `drm`, a
  wrapper around `navigator.requestMediaKeySystemAccess`), the Site Control Center shows a
  **Safari's Engine** switch. The request counts for the page whichever of its frames made it
  (`WidevineSignal` in CraCore): Fandango at Home's player is a frame of its own
  (`athome.fandango.com/bluesteel/player_frame.html`), and while only the top frame was asked
  that site never got the switch. Each frame's copy of the script tells the top frame's, in
  Cra's world, on a name that is random per launch: a frame of the page's own origin raises the
  event on the top window, and one of another origin posts a message, which the top frame stops
  at its own listener. **Not seen in Chromium:** a player frame from another site. It runs in
  another process, and Cra's page scripts go in through the page's own protocol session
  (`Page.addScriptToEvaluateOnNewDocument` in the bridge), which doesn't reach it. That needs
  the bridge to attach to such frames or to inject from the renderer. On, the site plays in WebKit from then on and the page reopens there.
  A WebKit page shows it on, so a listed site can be taken back to Chromium the same way
  (`ProtectedMediaSites.choosing`, kept in the data folder's `protected-media.json`). They are players, not whole domains, except where nothing else signs in through the service (Max sends `play.max.com` on to `www.hbomax.com` and signs in on its own hosts):
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

## Protected videos on an ordinary site

YouTube can't go on the list: every YouTube page would lose its extensions for the sake of the
few that play a bought film. So YouTube is a **mixed site** (`ProtectedMediaSites.defaultMixedSites`:
`youtube.com` and its subdomains, without `music.youtube.com`), and the engine is chosen per
page. `ProtectedVideoPages` (CraCore, `ProtectedVideos.swift`) holds the rules, with tests:

**Fandango at Home** (Vudu, `athome.fandango.com`) is a mixed site too, for another reason: it
has to arrive in WebKit signed in. Turned on whole with the Safari's Engine switch it arrived
signed out, and its play page then sends itself to `/content/account/login` and reloads, about
twice a second without end (19 Nov 2026; a plain `WKWebView` outside Cra does the same, and
Chromium lands on the sign-in page). As a mixed site the film's page asks, moves alone and takes
the session along. Its entry differs from YouTube's in three ways. The play path is the video
(`/content/browse/play/<id>/<kind>`; its `returnUrl` isn't, `pathNamesVideo`). Its session is
in cookies on `.fandango.com`, which is also Fandango's ticket shop, so that host's cookies are
copied without a switched page staying in WebKit there (`cookieHosts`). And only its play and
live pages are asked about (`videoPaths`): its front page asks for Widevine twice with nothing
playing, signed out too, and would otherwise get the prompt. A signed-out Chromium page is sent
to sign in before it plays, so it isn't moved.

- **When Cra asks:** a Chromium page of a mixed site that asks for Widevine, in any frame. The page tells Cra
  itself: PageScript's `drmNext()` in Cra's world is a promise Cra leaves waiting in the page
  (`BrowserManager.watchProtectedVideo`), which settles when the page calls
  `navigator.requestMediaKeySystemAccess('com.widevine…')`. Nothing polls. Once a page has
  asked, each `encrypted` media event counts as asking again, because a player that changes
  videos without a navigation may keep the key system it got. An ordinary YouTube video asks for
  neither (checked signed out, 19 Nov 2026), so it gets no prompt.
- **The prompt** is Cra's toast, staying until it is answered: "Protected video: better quality
  with Safari's engine, no extensions", with **Once** and **Always**. Its ✕ leaves that page in
  Chromium, and the page isn't asked about again in that tab (another video is). The toast goes
  with its page when another tab comes to the front and returns with it. An incognito page
  offers Once only, so no site is written to disk from it.
- **Once** moves this page to WebKit, at its address, in its split pane and with its focus
  (`BrowserManager.switchToSafariEngine`, the same reopening as the other handoffs). The place
  in the video goes along: in the address where the site has a time parameter (YouTube's
  `&t=754s`), else the WebKit page seeks its first video there once
  (`ProtectedVideoHandoff`). Under 5 seconds the video just starts over.
- **A page, not a site:** what was switched is the video (`ProtectedMediaSites.pageKey`: the
  site, the path and the `v` parameter; a time or a playlist don't make it another page). When
  the WebKit page's address becomes another video's, or no video's, the tab opens that address
  in Chromium again. YouTube changes videos without a navigation, so it is the address that is
  watched. The site's sign-in keeps the page in WebKit: Google's hosts,
  `accounts.youtube.com`, `consent.youtube.com` and `/signin`.
- **Always** is kept per site in `protected-media.json` as `protectedVideos` (not `added`, which
  is the whole site). From then on a page of that site that asks for Widevine moves without a
  prompt. The move is still that page's only.
- **Sign-in goes along:** before the move, the site's own cookies (YouTube: `youtube.com`,
  subdomains included; Fandango at Home: its own and `.fandango.com`'s) are copied from the tab's
  Chromium profile to the same profile's WebKit store (`Network.getAllCookies`, filtered by
  `ProtectedVideoHandoff.cookies`; partitioned and expired cookies stay). An incognito page's
  go to the incognito session's throwaway WebKit store and nowhere else. If the copy fails or
  takes over 2 seconds the page moves anyway and asks to sign in. Google's own cookies
  (`google.com`) are not copied (Victor, 20 Nov 2026): one film shouldn't put a whole Google
  account's sign-in in WebKit's store. YouTube keeps its sign-in on `.youtube.com` as well;
  whether that alone keeps the moved page signed in is a line in the release checklist. Google's
  sign-in pages still keep a moved page in WebKit, so signing in there lands back on it.
- **The Site Control Center's Safari's Engine row** says what is in force
  (`ProtectedVideoPages.row`) and its click changes it:

  | Row | Where | Click |
  |---|---|---|
  | On | a page of a site that plays in WebKit as a whole | the site goes back to Chromium (as before) |
  | Off | a Chromium page off the mixed sites that asked for Widevine | the site moves to WebKit (as before) |
  | Protected Videos | any page of a mixed site with Always | Always is taken back; a switched page returns to Chromium |
  | This Video | a page switched Once | the page returns to Chromium |
  | Off | a mixed site's Chromium page that asked and stayed | Always for the site, and this page moves (an incognito page: this page only) |

  A page taken back with the row isn't asked about again. A mixed site that someone added whole
  with the old switch is a whole-site entry and behaves as one.
- **On the switched page** the Site Control Center's Protected Media card and the dimmed
  extension buttons say "This video", not the site: the rest of YouTube keeps its extensions. The
  once-per-service "plays with Safari's engine" toast doesn't show for it; the prompt was the telling.

A switched page is remembered for the session only. After a relaunch its tab opens in Chromium,
where the film asks for Widevine again: with Always it moves by itself, otherwise the prompt
shows. Back doesn't cross the move: each engine keeps its own history, as with the other handoffs.
A player in a frame of the same site counts for its page here too. Known gaps: a player frame
from another site isn't seen (above), and Little Windows and Peeks don't prompt.

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
| `Cra.mediaSession`, `Cra.autoPictureInPicture` | never sent: a WebKit page's media session handlers go through PageScript's wrapper, and leaving its tab asks its video for Picture in Picture |

PageScript's scripts run in WebKit as user scripts, in the page world and in a `cra` content
world. With them come Cra's typed-text and long-task tracking, the sidebar player's media session
buttons (through a wrapper around `setActionHandler` that only WebKit pages get; Chromium routes a
page's handlers itself) and its volume. A small addition in the `cra` world reports what Chromium
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
  `told` list of `protected-media.json`. One left open shows again the next session.
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
- **Chromium's logins and cookies**: the first visit to a service signs in again. The exception
  is a page moved for a protected video on a mixed site, whose sign-in cookies are copied.
- **Chromium's site settings, content blocking, HTTPS-Only and fingerprinting protection**
  (fingerprinting-protection.patch is in Cra's Chromium): camera and microphone ask
  through Cra's prompt on every visit.
- **Chrome's DevTools**: Develop ▸ Developer Tools opens WebKit's Web Inspector in its own window.
- **Arc's Picture in Picture window**: the video goes to the system's own Picture in Picture
  window, with its controls. Auto Picture in Picture, the sidebar player's button and coming
  back to the tab work as for Chromium pages. WebKit has Picture in Picture off for apps other
  than Safari until its `allowsPictureInPictureMediaPlayback` preference is set (without it,
  `requestPictureInPicture()` answers NotSupportedError).
  View ▸ Picture in Picture takes WebKit's own toggle, as Safari's menu does (`_togglePictureInPicture`,
  `WebKitPictureInPicture` in CraCore; it did nothing on a WebKit page until #585), and a second ask puts
  the video back. The sidebar player's button asks the page first and goes on to the same toggle when
  the page has no video or turns the request down.
  The system window's ↖ button is its Back to Tab: WebKit reports the press through its private
  UI delegate call `_webViewFullscreenMayReturnToInline:` (Safari selects the tab there), and Cra
  selects the tab and brings its window up before the video lands. Until #585 the button did
  nothing: with the tab still hidden, the window stayed up. The window's ✕ pauses the video and
  puts it back without selecting anything.
  **A player that says no:** Netflix's player makes its video with `disablePictureInPicture`
  (the default in its player script), and Cra's ask skipped such a video, so nothing opened and
  the log said nothing. WebKit doesn't hold a request to the attribute (macOS 27: both
  `requestPictureInPicture()` and `webkitSetPresentationMode` open such a video, as Safari's own
  Enter Picture in Picture does), so on a WebKit page Cra now takes it like any other video:
  from View ▸ Picture in Picture, from the sidebar player's button, and as its tab is left
  (`PictureInPictureRequest` in CraCore). The Site Control Center's switch still turns leaving
  the tab off for a site. A Chromium page's opted-out video is left alone, because Chromium
  refuses the request. An ask that opens nothing says why in `cra.log` ("has no video for
  Picture in Picture", "refuses Picture in Picture: …"). A player inside an iframe of a WebKit page isn't reached: WebKit has
  no way to run the ask in every frame.
- **Chromium's fullscreen handling**: WebKit takes a fullscreen video to its own fullscreen
  window, as in Safari, and Esc leaves it. That window covers Cra's, so the covered-window
  auto Picture in Picture leaves a WebKit page in its own fullscreen alone
  (`PageEngines.isInOwnFullscreen`): a request made then got stuck in WebKit's transition, and
  that video never went to Picture in Picture again.
- **In-place tab sleep**: a sleeping WebKit page closes and loads its address again when shown.
  Its back/forward list goes with it.

## Settings

    defaults write dk.kildahl.cra webKitProtectedMedia -bool NO        # every page Chromium's again

The Safari's Engine choices and the closed toasts are in the data folder's `protected-media.json`
(`ProtectedMediaChoices`: `added`, `removed`, `told`, and `protectedVideos` for the mixed sites with
Always, written only once it has an entry), so each test instance (`CRA_DATA_DIR`) keeps
its own and never writes the daily Cra's. They are read at launch. A test instance takes `CRA_WEBKIT_DRM=0|1`,
`CRA_WEBKIT_HOSTS=<host,host>` (the scenarios list `localhost`) and `CRA_MIXED_HOSTS=<host,host>`
(its own mixed sites; `protected-video-prompt` lists `127.0.0.1`).

## Testing

- `swift test --package-path Packages/CraCore --filter "ProtectedMedia|ProtectedVideos"`: the rules.
- `Tests/test-browser-manager.sh` (`pageEngineCase`): the real `BrowserManager` and
  `PageEngines` choosing engines, popups keeping their opener's engine, and handoffs in both
  directions keeping the split, its order and its focus. `protectedVideoCase`: a mixed site's
  page asking for Widevine, Once with the time and the cookies, the next video going back, Always
  moving unasked, and the row taking it back.
- `scripts/scenario.sh widevine-in-a-frame`: a page whose player frame asks for Widevine
  (`frame-player.html`, the frame on the page's own origin as Fandango's is): the page's `drm`
  turns true, the page's own listener sees only the frame's own message, and the Site Control
  Center's switch shows and works. A frame of another origin is covered by the CraCore test only
  (`aFramesRequestCountsForItsPage`), on stand-in windows.
- `scripts/scenario.sh protected-video-prompt`: the running app on the fixture server as a
  mixed site (`film.html`). No prompt for an ordinary page; the prompt with Once, Always and ✕;
  Once moving only that page, with its place in the video and a cookie set in Chromium; the next
  page going back to Chromium; ✕ not asking twice; Always skipping the prompt; the Site Control
  Center's row saying what is in force and taking it back; a player frame asking for its page.
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
- `scripts/scenario.sh webkit-pip-opted-out` (#585): on a WebKit page whose video says no to
  Picture in Picture, View ▸ Picture in Picture opens it and a second ask puts it back, and
  leaving the tab opens it too; the system window's back-to-tab press (`cra://debug?pipBackToTab=1`,
  as WebKit reports it) brings the tab to the front. `webkit-drm-tabs` keeps its video in the page with the site's
  automatic Picture in Picture off (it used `disablePictureInPicture` for that until #585).
- Still by hand, with real accounts: Spotify plays track after track, Netflix and Disney+ play,
  and sign-in through Google or Apple comes back signed in. Peek from a pinned WebKit tab.
  Netflix's film opens in Picture in Picture from View ▸ Picture in Picture, from the sidebar
  player's button and when its tab is left.
- Fandango at Home, with an account (19 Nov 2026): before it was a mixed site, the frame's
  request showed the switch, and the switch turned on by hand gave the reload loop above. As a
  mixed site, a bought film's play page asked, moved signed in and played in Safari's engine.
- YouTube, with an account that owns a film (19 Nov 2026): the film's page moved to Safari's
  engine with its sign-in (71 cookies copied, Google's included) and played. Not looked at one by
  one: the quality it offers there, that the Chromium session stays signed in, and the resume from
  `&t=`. Since 20 Nov only `youtube.com`'s cookies go along; not yet tried with an account.
