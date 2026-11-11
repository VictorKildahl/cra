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
| Launch moment: logo behind the rising sheet | partial | Cra's mark shows behind the sheet; the rise follows the keyboard. Not compared frame by frame yet. |
| Search field: "Search...", caret, clear button | done | Measured: 48 pt field, 16 pt insets, 20 pt medium text, 18 pt clear disc. |
| Suggestions: typed text first, completions with the typed part grey | done | Measured rows (56 pt), magnifier, text. Engine's suggest endpoint, four rows. |
| Suggestion text wraps to two lines | missing | Rows are one line. |
| Site matches as rows (favicon and title) | missing | |
| Favorites / pinned sites under an empty field | missing | |
| Scrolling the suggestions updates the field | missing | |
| "Browse for Me" button on each search row | partial | Shown only where Apple Intelligence is on; opens the search for now. |
| Pill grows into the search field | partial | The morph exists; timing and the side icons' fade are not compared yet. |
| Tap above the sheet closes it | done | UI test `testThePillOpensSearchAndATapAboveClosesIt`. |
| Swipe the sheet down to close | missing | |
| Incognito toggle in the field | partial | Toggles and opens private tabs; no dark sheet, label or "You're browsing Incognito" yet. |
| Voice search (hold the pill, mic in the field) | missing | |
| Call Arc | *skip* | Removed from Arc Search itself. |
| Default search engine: Google, Bing, DuckDuckGo, Ecosia, Perplexity, Kagi, custom | partial | The six engines in App Settings ▸ Search Engine (`MobileSearchEngine`); no custom engines, no "Browse for Me" as an engine. |
| Fidget-spinner logo | missing | |

## Page

| Arc Search | Cra | Notes |
|---|---|---|
| Full-height page, no address bar | done | |
| Bottom bar: tab stack, pill, up arrow | done | Measured: 76 pt bar, 76 × 39 pill, 35 pt circle, stack of two leaning cards. |
| Bar hides on scroll down, returns on scroll up | done | Follows the site's "Collapse Bottom Bar" switch. |
| Swipe on the bar to cycle recent tabs | missing | |
| Swipe to navigate, from anywhere | partial | WebKit's edge swipe only. |
| Swipe back on a tab's first page archives it; opposite reopens | missing | |
| Pull to refresh | missing | |
| Page menu ("Tab Controls"): address capsule, tiles, rows, footer | done | Measured from Arc Search screenshots (`MobilePageMenu`): 48 pt capsule, 68 × 77 tiles, 48 pt rows. Back, forward, reload and the link glyph work. "Gift Arc" has no counterpart. UI tests in `PageMenuTests`. |
| Reader | missing | The tile is there and does nothing yet. |
| Find on Page | done | The system find bar; Arc Search's own bar was not seen in any source. |
| Copy Link without trackers, Share | done | `CleanURL`, from the tile and from the capsule's link glyph. |
| Page Zoom, Request Desktop Site | done | Tenths from 50% to 300%, the percentage shown and reset by a tap. |
| Translate | missing | The row is there and does nothing yet. |
| Pinch to Summarize / Summarize | missing | On-device model only. The tile is there (where the model is) and does nothing yet. |
| Block ads, trackers, cookie banners, per site | done | The Mac app's domain list compiled into WebKit content rules (`MobileBlocklist`), cookie banners hidden by their containers; each page gets the lists its site's switches ask for. The list does not say which domain is an ad and which a tracker, so the split is by name. Cookie prompts are hidden, not answered (Arc Search 1.38 denies them). |
| "Reload without ad blockers", blocked count | done | The tab shows the site unblocked until it leaves it. The footer counts requests to listed domains that failed while their blocker was on. UI test in `BlockingTests`. |
| Link long-press preview and menu | partial | WebKit's default preview. |
| New-window links open a tab | done | |
| Downloads, Wallet passes, .ics | missing | |
| Picture in picture, HTTP auth, certificate bypass | missing | |
| Open in native app banner, "Open App Links in..." | missing | |
| Handoff | missing | |

## Tabs

| Arc Search | Cra | Notes |
|---|---|---|
| Tab switcher: overlapping cards, newest right | done | Measured: 273 × 555 pt cards, 17 pt corners, focus card 83 pt in. `MobileTabCarousel`; UI tests in `TabSwitcherTests`. |
| Page shrinks into its card and back | partial | Spring morph exists; not compared frame by frame. |
| Swipe a card up to close | done | |
| Favicon and title above each card | done | Icons come from the site itself. |
| Switcher bar: Spaces, "+", Settings | partial | The gear opens App Settings. The left button is still the archive of the 1.0 footage, not Spaces. |
| Auto-archive: 12 hours, 1 day, 3 days, 7 days, 30 days | done | App Settings ▸ Archive Inactive Tabs; applied at launch. |
| Archive list: search, day groups, edit, swipe to delete | done | `MobileArchive`; a tap reopens the tab. UI test `testAnArchivedTabComesBackFromTheArchive`. |
| Incognito tabs kept out of the switcher and off disk | partial | Never saved; still shown in the switcher. |
| Clear Browsing Data | done | Clear History empties the archive; Clear Cookies and Site Data empties WebKit's store. |
| Export Data | done | The open tabs as text through the share sheet. |

## Spaces and saving

| Arc Search | Cra | Notes |
|---|---|---|
| Spaces from the desktop: pinned tabs, folders, Today | missing | Plan: read the Mac app's synced `sidebar.json` from iCloud. |
| Pin from the phone ("Favorite in App", "Pin to Space:") | missing | |
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
