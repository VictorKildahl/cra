# Arc Search parity (iPhone app)

Arc Search 1.49.0 feature by feature, against Cra for iPhone on the `ios-app` branch. The
feature list comes from [arc-search-reference.md](arc-search-reference.md) (sections B and C);
[ios.md](ios.md) says how a screen is measured and compared.

Status: **done** = built and compared with the reference; **partial** = some of it;
**missing** = nothing yet; *skip* = left out on purpose (account, cloud AI, a service that
ended). "Measured" means the numbers come from Arc Search footage, not from a description.

## Search and launch

| Arc Search | Cra | Notes |
|---|---|---|
| Opens ready to type: sheet and keyboard up | done | Measured. `MobileSearchSheet`; UI test `testLaunchesReadyToType`. |
| Launch moment: logo behind the rising sheet | partial | Cra's mark shows behind the sheet. Measured frame by frame, Arc Search's sheet rises on the keyboard's own curve while growing from the bar's height to 302 pt, which is how this one moves (it animates inside the keyboard's animation). The logo's own motion is not matched. |
| Search field: "Search...", caret, clear button | done | Measured: 48 pt field, 16 pt insets, 20 pt medium text, 18 pt clear disc. |
| Suggestions: typed text first, completions with the typed part grey | done | Measured rows (56 pt), magnifier, text. Engine's suggest endpoint, four rows. |
| Suggestion text wraps to two lines | missing | Rows are one line. |
| Site matches as rows (favicon and title) | missing | |
| Favorites / pinned sites under an empty field | partial | The first four of "Favorite in App" (`MobileFavorites`), each with its site icon and a pin. No drag to reorder. |
| Scrolling the suggestions updates the field | missing | |
| "Browse for Me" button on each search row | done | Shown only where Apple Intelligence is on. |
| Pill grows into the search field | partial | The morph exists; timing and the side icons' fade are not compared yet. |
| Tap above the sheet closes it | done | UI test `testThePillOpensSearchAndATapAboveClosesIt`. |
| Swipe the sheet down to close | done | The sheet follows the finger; the keyboard leaves on release. |
| Incognito toggle in the field | done | The sheet turns dark with "Incognito" beside the mask, "You're browsing Incognito" and the dark keyboard; colours from the store screenshot. Suggestions are not fetched while it is on. |
| Voice search (hold the pill, mic in the field) | missing | |
| Call Arc | *skip* | Removed from Arc Search itself. |
| Default search engine: Google, Bing, DuckDuckGo, Ecosia, Perplexity, Kagi, custom | partial | The six engines in App Settings ▸ Search Engine (`MobileSearchEngine`); no custom engines, no "Browse for Me" as an engine. |
| Fidget-spinner logo | missing | |

## Browse for Me

| Arc Search | Cra | Notes |
|---|---|---|
| Reads several pages and makes one page of the answer | done | All on the phone (`MobileBrowseForMe`, `BrowseForMe`): results from DuckDuckGo's plain HTML page, six sites fetched and read, the device's own model writes the title, key points and sections. No answer (no results, no network, a refusal) falls back to the search engine. The query therefore goes to DuckDuckGo whatever the search engine setting is. |
| Loading screen: query, rising gradient, "Reading N web pages", the sites, "Making a website for you" | partial | Built to the 1.0 footage (positions measured, SF Rounded standing in for Arc's own typeface). The 1.22 redesign with query editing was not seen. |
| Result page: query capsule, pictures, "Read N web pages", source cards, blue title, emoji key points, sections | partial | In that order. No video carousel, "Learn more", follow-up chips, list format, instant answers or feedback block. |
| Toggle between Browse for Me and the search engine | partial | The query capsule opens the search engine's results; no floating two-segment control. |
| Its own tab, restored after a relaunch | done | The page is kept in the caches folder; incognito pages are not. |
| Browse for Me as the search engine, from selected text, from the share sheet, Shortcuts | missing | |

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
| Translate | missing | The row is there and does nothing yet. |
| Pinch to Summarize / Summarize | partial | The tile and the pinch summarize with the device's own model (`MobileSummary`, `Summarizer`): the page shrinks into its folded card, then the overview and titled sections, "Summarized for you by Cra" and the close button. Follows the site's Pinch to Summarize switch. The origami fold itself, the wiggle while loading, and copy/share of the summary are not built. |
| Block ads, trackers, cookie banners, per site | done | The Mac app's domain list compiled into WebKit content rules (`MobileBlocklist`), cookie banners hidden by their containers; each page gets the lists its site's switches ask for. The list does not say which domain is an ad and which a tracker, so the split is by name. Cookie prompts are hidden, not answered (Arc Search 1.38 denies them). |
| "Reload without ad blockers", blocked count | done | The tab shows the site unblocked until it leaves it. The footer counts requests to listed domains that failed while their blocker was on. UI test in `BlockingTests`. |
| Link long-press preview and menu | partial | WebKit's default preview. |
| Hold the up arrow for the share sheet | done | |
| New-window links open a tab | done | |
| Downloads, Wallet passes, .ics | missing | |
| Picture in picture, HTTP auth, certificate bypass | missing | |
| Open in native app banner, "Open App Links in..." | missing | |
| Handoff | missing | |

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
| Share extension with "Saved" screen | missing | |
| Sign in with Arc | *skip* | No account in Cra; iCloud carries the sync. |

## Settings

| Arc Search | Cra | Notes |
|---|---|---|
| Site Settings sheet | done | Same rows and order; 465 pt tall over the page menu. Compared with a late-2024 screenshot. |
| App Settings | partial | Archive, Global Site Settings, default browser, Search Engine, Archive Inactive Tabs, keyboard on launch, Open App Links in..., Clear Browsing Data, Export Data. No Downloads, Languages or app icons yet. The order below Archive Inactive Tabs is a guess: no source shows it. |
| Clear Data sheet | done | |
| Onboarding | missing | |
| Alternate app icons | missing | |

## System

| Arc Search | Cra | Notes |
|---|---|---|
| Default browser | partial | Declares http/https; the `com.apple.developer.web-browser` entitlement needs Apple's approval. |
| Widgets (small, medium, Lock Screen) | missing | |
| App Shortcuts, quick actions | missing | |
| iPad layout | partial | Runs; nothing iPad-specific. |
| Landscape | partial | Rotates; not checked. |
| Dynamic Type | missing | |
| Dark mode | partial | Colours defined; not compared with a reference. |
| System look | done | `UIDesignRequiresCompatibility`: Arc Search's lists, sheets and keyboard are the pre-iOS 26 ones. |
