# Arc Search parity (iPhone app)

Arc Search 1.49.0 feature by feature, against Cra for iPhone on the `ios-app` branch. The
feature list comes from [arc-search-reference.md](arc-search-reference.md) (sections B and C);
[ios.md](ios.md) says how a screen is measured and compared.

Status: **done** = built and compared with the reference; **partial** = some of it;
**missing** = nothing yet; *skip* = left out on purpose (account, cloud AI, a service that
ended). "Measured" means the numbers come from Arc Search footage, not from a description.

## Where this stopped (12 November 2026)

Work was paused mid-way. The branch is `ios-app`, in the worktree `../cra-ios`; nothing is
pushed. Pick up here.

**State of the tests.** 13 November, morning: every UI test passed (50, run in two halves);
under the Mac's load at the time (security agents at a load average of several hundred) some were
killed by the system ("signal term/kill") and passed on a second or third run, never failing an
assertion. The CraCore tests (`--filter Mobile`) pass. Run the suite in two halves; do not edit
sources while it runs; when the simulator keeps shutting down, `killall -9
com.apple.CoreSimulator.CoreSimulatorService` and boot it again.

**Checked in the running app since the pause:** the empty home screen with its logo, the page
pushed back behind the search sheet. **Still built but not verified:** the widget extension
(`iOS/CraWidgets`) and its links `cra://search`, `cra://voice`, `cra://spaces`; the
certificate warning, HTTP sign-in, link long-press menu and Handoff.

**Next, in this order:**
1. Look at the widgets in the simulator's widget gallery.
2. Scrolling the suggestions updates the field (needs the reference clip, YouTube KRX1EXj6LaI at
   0:31, fetched through the Cra MCP; `curl` is not allowed here).
3. Translate (on-device Translation framework; it does not run in the simulator).
4. Browse for Me: the floating toggle to the search engine, Browse for Me as a search engine.
5. iCloud entitlement for Spaces, then writing pins back to the Mac ("Pin to Space:"). Needs
   Victor's Apple ID; so does running on his iPhone, which has never been done.
6. Share extension; Languages; custom search engines; iPad and landscape; dark mode against a reference.
7. Motion still unmeasured: the pill growing into the search field, the summarize fold.

**Pin to Space: a proposal, waiting for Victor.** Arc Search's "Pin to Space:" writes into the
desktop's sidebar. The Mac's sync folder (`SettingsSync`) is a bundle each Mac writes whole, manifest
last; the phone writing `sidebar.json` would race the Macs and break that rule. Proposed instead: the
phone writes `phone-pins.json` beside the bundle (entries: id, url, title, Space id, optional folder id,
created), which a Mac that knows it reads on its next look, adds as pinned tabs, records as applied in
its own `sync.json` state, and then writes a normal bundle. Older Macs ignore the file. The phone drops
an entry once the Mac's `sidebar.json` holds it (or after 30 days). This is a data-folder format change
(CLAUDE.md rule 4) with a reader on main, so it is Victor's call before it is built.

**The reference.** Arc Search cannot be installed in the simulator (no App Store there, no Mac
build). The footage and screenshots used are in `build/ios-reference/` of the worktree (not in
git); [arc-search-reference.md](arc-search-reference.md) lists more. On 23 November 2026 Arc
Search's Browse for Me, summaries and sync are switched off, so anything to be recorded from
the real app on an iPhone has to be recorded before then.

## Search and launch

| Arc Search | Cra | Notes |
|---|---|---|
| Opens ready to type: sheet and keyboard up | done | Measured. `MobileSearchSheet`; UI test `testLaunchesReadyToType`. |
| Launch moment: logo behind the rising sheet | partial | Cra's mark shows behind the sheet. Measured frame by frame, Arc Search's sheet rises on the keyboard's own curve while growing from the bar's height to 302 pt, which is how this one moves (it animates inside the keyboard's animation). The logo's own motion is not matched. |
| Search field: "Search...", caret, clear button | done | Measured: 48 pt field, 16 pt insets, 20 pt medium text, 18 pt clear disc. Colours follow TapSmart's March 2025 screenshot (same 1206 × 2622 size as the simulator, compared pixel for pixel): sheet #f3f3f4 warming to #f3e6e8, flat grey field #dbd9da, grey chips, the clear disc's cross cut out. The 2024 footage's lavender field is gone. |
| Suggestions: typed text first, completions with the typed part grey | done | Measured rows (56 pt), magnifier, text. Engine's suggest endpoint, four rows. |
| Suggestion text wraps to two lines | done | A long suggestion takes a second line in the same 56 pt row and is cut after it. |
| Site matches as rows (favicon and title) | done | Favorites, open and archived tabs (`MobileSuggestions.siteMatches`): a site whose address starts with what was typed leads the list, a title match follows the typed text, two at most. Arc Search's order was read from one Feb 2024 picture (site rows above and below the query row), not measured. Not offered while incognito. UI test `testAnOpenPageIsOfferedWhenItsAddressIsTyped`. |
| Favorites / pinned sites under an empty field | partial | The first four of "Favorite in App" (`MobileFavorites`), each with its site icon and a pin. No drag to reorder. |
| Scrolling the suggestions updates the field | partial | Ten rows, four in view; dragging them up passes each under the field, which takes its text, and back at the top shows what was typed (`MobileSuggestions.Scroll`, from 60fps.design's "Arc Search Scroll Morph" clip). A flick rests on a whole row. The field crossfades where Arc Search keeps the shared beginning still and morphs the rest. UI test `testScrollingTheSuggestionsPutsEachInTheField`. |
| "Browse for Me" button on each search row | done | Shown only where Apple Intelligence is on. |
| Pill grows into the search field | partial | The morph exists; timing and the side icons' fade are not compared yet. |
| Tap above the sheet closes it | done | UI test `testThePillOpensSearchAndATapAboveClosesIt`. |
| Page pushed back as a dimmed card behind the sheet | done | Placed from the TidBITS screenshot (`MobilePageBehindSearch`): 10 pt in from each side, top under the status bar, black at 0.2 over it (a white page reads #cccccc, as there). Checked in the app. |
| Swipe the sheet down to close | done | The sheet follows the finger; the keyboard leaves on release. |
| Incognito toggle in the field | done | The sheet turns dark with "Incognito" beside the mask, "You're browsing Incognito" and the dark keyboard; colours from the store screenshot. Suggestions are not fetched while it is on. |
| Voice search (hold the pill, mic in the field) | partial | Hold the pill and speak; letting go searches for what was heard (`VoiceSearch`, `VoiceOverlayView`): dimmed page, glow, smiley, "Hi! How can I help?", the words in a capsule, dots that move with the voice. Speech is recognized on the device only. Built from a description and one small picture, not measured. The mic in the empty field (left of the incognito eyes, as in 60fps.design's incognito clip) starts it hands free, a tap ends it; UI test `testTheMicInTheFieldSearchesForWhatWasSaid`. The widget's mic and the Voice Search shortcut start it too. |
| Call Arc | *skip* | Removed from Arc Search itself. |
| Default search engine: Browse for Me, Google, Bing, DuckDuckGo, Ecosia, Perplexity, Kagi, custom | done | App Settings ▸ Search Engine lists Browse for Me first (only with the device's own model), the six engines, then Custom (`MobileSearchChoice`, `MobileSearch`). Custom asks for an https address with %s for the query; the row then shows its site, suggestions are off for it, and the Browse for Me switch reads its results. With Browse for Me picked, Go, voice and widget searches make a Browse for Me page. Arc Search's custom-engine editor was not seen. UI tests `testBrowseForMeCanBeTheSearchEngine`, `testACustomEngineTakesTheSearch`. |
| Fidget-spinner logo | partial | The mark on the empty home screen spins when flicked, slows and settles upright (`MobileFidget`, `FidgetLogoView`). Built, not yet verified in the app. |

## Browse for Me

| Arc Search | Cra | Notes |
|---|---|---|
| Reads several pages and makes one page of the answer | done | All on the phone (`MobileBrowseForMe`, `BrowseForMe`): results from DuckDuckGo's plain HTML page, six sites fetched and read, the device's own model writes the title, key points and sections. No answer (no results, no network, a refusal) falls back to the search engine. The query therefore goes to DuckDuckGo whatever the search engine setting is. |
| Loading screen: query, rising gradient, "Reading N web pages", the sites, "Making a website for you" | partial | Built to the 1.0 footage (positions measured, SF Rounded standing in for Arc's own typeface). The 1.22 redesign with query editing was not seen. |
| Result page: query capsule, pictures, "Read N web pages", source cards, blue title, emoji key points, sections | partial | In that order. No video carousel, "Learn more", follow-up chips, list format, instant answers or feedback block. |
| Toggle between Browse for Me and the search engine | done | The floating switch above the bar at the right, measured on TapSmart's March 2025 screenshot (`MobileBrowseToggle`): 108 × 43 pt capsule, the side on screen filled (Browse for Me with the #583dae to #c3699d gradient). On Browse for Me pages and on the chosen engine's results; the engine side loads its results in the tab, Browse for Me brings the page back from the cache. The filled engine side and the glyphs are Cra's own (Arc Search's mark and the engine's logo are theirs). UI test `testTheSwitchMovesBetweenBrowseForMeAndTheSearchEngine` (needs the network). |
| Its own tab, restored after a relaunch | done | The page is kept in the caches folder; incognito pages are not. |
| Browse for Me as the search engine, from selected text, from the share sheet, Shortcuts | partial | As the search engine: done (above). Selected text: "Browse for Me" after Copy in a page's edit menu, the selection as the question (`MobileBrowseForMe.query(fromSelection:)`, 200 characters at most); UI test `testSelectedTextCanBeBrowsedFor`. Arc Search's own placement in that menu was not seen. Shortcuts: a "Browse for Me" action with the question (`BrowseForMeIntent`, Siri phrase "Browse for Me with Cra"), a search where the device can't make the page; built, not run through Shortcuts yet. The share sheet: missing. |

## Page

| Arc Search | Cra | Notes |
|---|---|---|
| Full-height page, no address bar | done | |
| Bottom bar: tab stack, pill, up arrow | done | Measured: 76 pt bar, 76 × 39 pill, 35 pt circle, stack of two leaning cards. |
| Bar hides on scroll down, returns on scroll up | done | Follows the site's "Collapse Bottom Bar" switch. |
| Swipe on the bar to cycle recent tabs | done | The neighbouring tab in the row slides in beside the page (`MobileSwipe.tabStep`). Arc Search's own motion was not seen. |
| Swipe to navigate, from anywhere | partial | Back and forward from anywhere or from the edges, per site. The page slides off and the next one fades in; WebKit's own snapshot transition is not used, and Arc Search's was not seen. |
| Swipe back on a tab's first page archives it; opposite reopens | done | `MobileSwipe.navigation`; UI test in `GestureTests`. |
| Pull to refresh | done | Acts on release past 96 pt, so dragging back up cancels. The reload arrow is Cra's own: Arc Search's indicator was not seen. |
| Page menu ("Tab Controls"): address capsule, tiles, rows, footer | done | Measured from Arc Search screenshots (`MobilePageMenu`): 48 pt capsule, 68 × 77 tiles, 48 pt rows. Back, forward, reload and the link glyph work. "Gift Arc" has no counterpart. UI tests in `PageMenuTests`. |
| Reader | partial | The article alone, scripts off, in the device's serif (`Article`, `ReaderView`); a link leaves Reader. Arc Search's Reader was not seen in any source, so the look is Cra's own. |
| Find on Page | done | The system find bar; Arc Search's own bar was not seen in any source. |
| Copy Link without trackers, Share | done | `CleanURL`, from the tile and from the capsule's link glyph. |
| Page Zoom, Request Desktop Site | done | Tenths from 50% to 300%, the percentage shown and reset by a tap. |
| Translate | partial | The page menu's Translate turns the page into the phone's language on the phone itself (Apple's Translation framework, iOS 18), where Arc Search sends it to Google Translate: the visible text is collected node by node, translated in batches and written back (`MobileTranslate`); the row then reads "Show Original". The system's download prompt stands in for Arc Search's allow once/always. The framework does not run in the simulator, so the real translation is unchecked until it runs on an iPhone; UI test `testTranslateAndShowOriginal` covers the page side with a stand-in. No automatic offer on foreign pages, no per-site "always". |
| Pinch to Summarize / Summarize | partial | The tile and the pinch summarize with the device's own model (`MobileSummary`, `Summarizer`): the page shrinks into its folded card, then the overview and titled sections, "Summarized for you by Cra" and the close button. Follows the site's Pinch to Summarize switch. Copy and Share in the footer once it is written (the page's title, the summary, the credit and the page's address without trackers; `MobileSummary.Answer.plainText`). The fold, from the App Store preview (14.3–15.0 s): the page tips flat into a strip at mid-height, the card unfolds there and rises into place with a slight tilt; Reduce Motion keeps a plain shrink. Looked at frame by frame in the simulator; `testSummarizeShowsTheSummaryAndClosesBackToThePage` passes. The wiggle while loading is not built. |
| Block ads, trackers, cookie banners, per site | done | The Mac app's domain list compiled into WebKit content rules (`MobileBlocklist`), cookie banners hidden by their containers; each page gets the lists its site's switches ask for. The list does not say which domain is an ad and which a tracker, so the split is by name. Cookie prompts are hidden, not answered (Arc Search 1.38 denies them). |
| "Reload without ad blockers", blocked count | done | The tab shows the site unblocked until it leaves it. The footer counts requests to listed domains that failed while their blocker was on. UI test in `BlockingTests`. |
| Link long-press preview and menu | partial | Open, Open in New Tab, Copy Link (without trackers), Share. Arc Search's own items and its website preview were not seen. |
| Hold the up arrow for the share sheet | done | |
| New-window links open a tab | done | |
| Downloads, Wallet passes, .ics | partial | Files go to Documents/Downloads (shown in the Files app), numbered when a name is taken (`MobileDownloads`), announced above the bar and listed under Settings ▸ Downloads; a Wallet pass opens in Wallet, anything else in a preview. No .ics-to-calendar or .mobileconfig handling. |
| Picture in picture, HTTP auth, certificate bypass | partial | Sign-in prompts for HTTP authentication; a page whose certificate can't be verified says so and lets the user continue to that host for the rest of the run. Page alerts, confirms and prompts show. Picture in picture is WebKit's default and not checked. |
| Open in native app banner, "Open App Links in..." | partial | "Open App Links in..." works (App Settings, Native App by default as in 1.36): a link tapped in a page to another site goes to the app that claims it as a universal link, otherwise it loads in Cra (`MobileAppLinks.offersApp`); typed addresses, redirects and same-site links stay. The banner can't be built: iOS doesn't tell a browser which apps are installed. UI test `testALinkNoAppClaimsLoadsHere` (needs the network). |
| Handoff | done | The page on screen is offered to the user's other devices; never an incognito page. Not checked on a device. |

## Tabs

| Arc Search | Cra | Notes |
|---|---|---|
| Tab switcher: overlapping cards, newest right | done | Measured: 273 × 555 pt cards, 17 pt corners, focus card 83 pt in. `MobileTabCarousel`; UI tests in `TabSwitcherTests`. |
| Page shrinks into its card and back | done | Springs fitted to the footage (`MobileMotion`): the row settles with a critically damped 0.34 s spring (the card's distance shrinks to about 0.54 of itself each frame), a card is its page within five frames. A drag up from the bar shrinks the page under the finger and lets go into the row. |
| Swipe a card up to close | done | |
| Favicon and title above each card | done | Icons come from the site itself. |
| Switcher bar: Spaces, "+", Settings | done | |
| Auto-archive: 12 hours, 1 day, 3 days, 7 days, 30 days | done | App Settings ▸ Archive Inactive Tabs; applied at launch. |
| Archive list: search, day groups, edit, swipe to delete | done | `MobileArchive`; a tap reopens the tab. UI test `testAnArchivedTabComesBackFromTheArchive`. |
| Incognito tabs kept out of the switcher and off disk | done | Not in the row, the Archive or `tabs.json`, on a private data store. One that is left closes (inferred: with no card there is no way back to it). How an incognito page's own chrome differs was not seen. |
| Clear Browsing Data | done | Clear History empties the archive; Clear Cookies and Site Data empties WebKit's store. |
| Export Data | done | The open tabs as text through the share sheet. |

## Spaces and saving

| Arc Search | Cra | Notes |
|---|---|---|
| Spaces from the desktop: pinned tabs, folders, Today | partial | The tab row's left button opens them (`MobileSpaces`, `SyncedSidebar`): one Space a page in its colour, folders that fold, Today under a line, the Spaces' icons along the bottom; a tap opens the tab here. Read from the `sidebar.json` the Mac app syncs to iCloud. The iCloud entitlement is not in the project yet, so only the test folder (`-CraSyncDir`) has been exercised; the widget's Spaces button is missing. |
| Pin from the phone ("Favorite in App", "Pin to Space:") | partial | The page menu's pin has "Favorite in App". "Pin to Space:" and "Pin to Folder…" need the phone to write the Mac's sidebar, which it does not do yet. |
| Share extension with "Saved" screen | done | "Cra" in other apps' share sheets (`iOS/CraShare`): the gradient sheet, heart with a check, "Saved", the place picker (remembers the last place) and Done, laid out from TidBITS' April 2024 screenshot; the gradient approximates Arc Search's mesh. Done keeps the link in the App Group inbox (`MobileShareInbox`); swiping down saves nothing. The places are the phone's Tabs and Favorites: Arc Search's are Spaces, which needs the phone to write the Mac's sidebar. UI tests in `ShareExtensionTests` (the share-sheet one needs the network). |
| Sign in with Arc | *skip* | No account in Cra; iCloud carries the sync. |

## Settings

| Arc Search | Cra | Notes |
|---|---|---|
| Site Settings sheet | done | Same rows and order; 465 pt tall over the page menu. Compared with a late-2024 screenshot. |
| App Settings | partial | Order from 60fps.design's late-2024 clip below Set as Default Browser: Change App Icon and Add to Home Screen; Search Engine; Auto-Open Keyboard, Archive Inactive Tabs, Open App Links in..., Clear Browsing Data..., Export Data. Above that (not in the clip): Downloads and Archive, Global Site Settings, Set Cra as Default Browser. Languages (under Search Engine): the language Browse for Me, summaries and Translate answer in, "Same as iPhone" by default (`MobileLanguages`, the on-device model's languages); Arc Search's own Languages screen was not seen, only that answers follow the language preference (1.33). UI test `testLanguagesKeepsTheChosenLanguage`. Raise to Call Arc and Sync with Arc Desktop have no counterpart. |
| Clear Data sheet | done | |
| Onboarding | partial | Arc Search's steps and words (`MobileOnboarding`): welcome on the vivid gradient, "Meet your new favorite browser" with its four cards, the Browse for Me step where the device can, the icon grid, "Block Ads and Trackers", the default browser with Skip. The try-it demos (tapping Browse for Me, the pinch tip with its check mark) and the gradient's own transition are simplified. Settings ▸ Show Onboarding brings it back. Since 13 Nov also Arc Search's step 5, "*Pinch* to summarize any web page" on the vivid gradient, acted out on a loop after 60fps.design's clip (pinch, fold, "Summarizing for you…", the summary and a check); Arc Search's separate summary step 6 and its Skip are folded into it. |
| Alternate app icons | done | Cra's four (`MobileAppIcon`), rendered for iOS by `scripts/make-app-icons.swift --ios`; picked in onboarding, and from App Settings ▸ Change App Icon in Arc Search's dock sheet (`AppIconDock`, from 60fps.design's clip): the icons on a glass shelf with their reflections, the current one raised with a blue dot; iOS confirms the change in its own alert. UI test `testChangeAppIconShowsTheDock`. |

## System

| Arc Search | Cra | Notes |
|---|---|---|
| Default browser | partial | Declares http/https; the `com.apple.developer.web-browser` entitlement needs Apple's approval. |
| Widgets (small, medium, Lock Screen) | partial | `iOS/CraWidgets`, looked at in the simulator's widget gallery. Small is Arc Search's, from 60fps.design's "Add Widget" clip: the indigo-to-pink gradient, the mark at the top left, the white Search capsule running off the right edge, voice and Spaces buttons along the bottom (their own links through `OpenURLIntent` on iOS 18; the whole widget searches before that). Medium (Arc Search's not seen) has the same parts with Voice and Spaces labelled; Lock Screen circular and rectangular. "Bring Cra to your home screen" (`WidgetGuideView`, App Settings ▸ Add Widget): Arc Search's three steps from the same clip (the widget with Add Widget and Maybe Later; "Start by holding anywhere"; "Tap Edit and select Add Widget") with a drawn home screen acting each out on a loop; colours measured there. The italics in the titles don't show in the rounded font, and how Arc Search opens the walkthrough was not seen. UI test `testTheWidgetGuideWalksThroughItsSteps`. |
| App Shortcuts, quick actions | done | "Search with Cra" and "Voice Search with Cra" for Siri, Spotlight and the Action button (`AppShortcuts.swift`); home-screen quick actions Change App Icon, Voice Search, Search. Not exercised by a test: they are started from outside the app. |
| iPad layout | partial | Runs; nothing iPad-specific. |
| Landscape | partial | Rotates; not checked. |
| Dynamic Type | missing | |
| Dark mode | partial | The search sheet compared with 60fps.design's dark-mode clip: sheet #2e2930 with its faint blue glow behind the rows, field #433f44 (the clip is compressed video: within a few levels). The rest of the chrome's dark colours are not compared yet. |
| System look | done | `UIDesignRequiresCompatibility`: Arc Search's lists, sheets and keyboard are the pre-iOS 26 ones. |
