# Arc Search for iOS/iPadOS: feature and UI inventory

Compiled 11 Nov 2026 from published material only (the app was not run). App Store id 6472513080, bundle id company.thebrowser.ArcMobile2, current version 1.49.0.

## How to read this document

- Every claim carries a source tag in square brackets. Tags are keys from the source legend below; each key is one URL.
- `[img KEY-n]` means I opened that image file myself and transcribed what is visible. Those labels are verbatim. Everything tagged with a plain article key came through a summarising fetch, so wording of UI labels from those is "as the article reports it", not checked against pixels.
- "(inferred)" marks anything I concluded rather than read. "Not found" means I looked and no source had it.
- Dates on screenshots matter: the UI changed a lot between Jan 2024 and mid 2024. Each transcription says which build or date it comes from. The most recent real screenshots I could read are from 24 Mar 2025 (about v1.42). Releases after 1.42 are described by the vendor as fixes only, plus an Export Data row (Oct 2026) and the removal of Call Arc, so "latest UI" in section C means "v1.42-era UI plus those noted changes" (inferred).
- Sources that could not be reached: theverge.com, reddit.com, web.archive.org and archive.ph are blocked for the fetch tool; resources.arc.net HTML returns 403 (its Zendesk JSON API works, and that is what the RN/HC keys below were read through); YouTube transcripts were not retrievable (titles, descriptions and chapters were). The old feature help articles (ids 20887042551831, 20272860828823, 25482594475031, 27777981625495) return 404: the help centre was rewritten for the sunset and now has 22 articles.

## Source legend

Vendor
- RN: https://resources.arc.net/hc/en-us/articles/23528454620311-Arc-Search-for-iOS-Release-Notes (read via https://resources.arc.net/api/v2/help_center/en-us/articles/23528454620311.json)
- HC: https://resources.arc.net/hc/en-us/articles/25482329571479-Arc-for-iOS-Android-Arc-Search (sunset-era FAQ; via the same API)
- MACRN: https://resources.arc.net/hc/en-us/articles/20498293324823 (Arc for macOS release notes; entries that mention Arc Search)
- ANDRN: https://resources.arc.net/hc/en-us/articles/27306904379031-Arc-Search-for-Android-Release-Notes (Android only; used for cross-reference, never as evidence for iOS)
- AS: https://apps.apple.com/us/app/arc-search-find-it-faster/id6472513080 (version history, last 25 entries; also read on the gb and ca storefronts)
- ITL: https://itunes.apple.com/lookup?id=6472513080&country=us (metadata, description, screenshot URLs)
- FAREWELL: https://arc.net/search (now redirects to the "A farewell to Arc" page)
- X-JM1: https://twitter.com/joshm/status/1751734580124787028 ; X-JM2: https://twitter.com/joshm/status/1751735523704701247 ; X-JM3: https://twitter.com/joshm/status/1760698068943724634 ; X-NP: https://twitter.com/nateparrott/status/1793643577605796307 (texts read via api.fxtwitter.com)
- YT-xxxx: https://www.youtube.com/watch?v=xxxx (The Browser Company channel; metadata and chapters only)

Reviews and guides
- MS: https://www.macstories.net/reviews/arc-search-for-iphone/ (Federico Viticci, 29 Jan 2024, v1.0)
- TC1: https://techcrunch.com/2024/01/28/arcs-new-iphone-browser-wants-to-be-your-search-companion/
- TC2: https://techcrunch.com/2024/05/23/arc-searchs-new-call-arc-feature-lets-you-ask-questions-by-making-a-phone-call
- MR1: https://www.macrumors.com/2024/01/29/arc-search-iphone-app-ai/
- MR2: https://www.macrumors.com/2024/05/23/arc-search-call-feature/
- GZ: https://gigazine.net/gsc_news/en/20240130-arc-search-review (30 Jan 2024)
- TR: https://techround.co.uk/news/arc-a-new-search-engine-is-now-available-for-ios/ (30 Jan 2024)
- ATH1: https://allthings.how/how-to-set-arc-search-as-default-browser-on-iphone/ (30 Jan 2024)
- ATH2: https://allthings.how/using-browse-for-me-in-arc-search/ (30 Jan 2024)
- ATH3: https://allthings.how/how-to-enable-and-use-arc-sync-in-arc-search-browser-on-iphone (26 Apr 2024)
- ATH4: https://allthings.how/what-is-call-arc-in-arc-search-and-how-can-you-access-it/ (7 Jun 2024)
- TB1: https://tidbits.com/2024/02/15/arc-gains-instant-links-tab-grouping-and-arc-search-iphone-app/
- TB2: https://tidbits.com/2024/04/29/arc-search-iphone-app-now-syncs-arc-sidebar-tabs/
- SG: https://www.slashgear.com/1518162/how-to-use-arc-browser-on-iphone/ (20 Feb 2024)
- ANT: https://www.appsntips.com/arc-search-review/ (Feb 2024, screenshots of v1.2.0)
- ALT: https://alternativeto.net/news/2024/2/arc-introduces-new-ai-powered-pinch-to-summarize-feature-for-swift-webpage-summaries (23 Feb 2024)
- TCAT: https://www.testingcatalog.com/arc-browsers-latest-ios-feature-pinch-to-summarize-rolled-out-for-efficient-web-browsing/ (22 Feb 2024)
- SPY: https://spyglass.org/pinch-to-summarize/ (22 Feb 2024)
- INV: https://www.inverse.com/tech/arc-search-ios-app-interview-lead-designer-engineer (29 Jan 2024; interview with lead designer Karla Mickens and lead engineer Adam Stern)
- TH: https://www.thurrott.com/?p=301442 (25 Apr 2024)
- 9A: https://9to5mac.com/2024/05/02/arc-search-adds-widgets-voice-search/
- 9B: https://9to5mac.com/2024/05/23/arc-goes-conversational-with-call-arc/
- MC1: https://matthewcassinelli.com/arc-search-iphone-call-for-answers-action-button-shortcuts/ ; MC2: https://matthewcassinelli.com/new-in-the-shortcuts-library-arc-search-shortcuts/ ; MC3: https://matthewcassinelli.com/arc-search-updated-to-be-usable-on-ipad-tablet-specific-design-comes-later/
- IFUN: https://www.ifun.de/arc-search-jetzt-auch-als-ipad-app-verfuegbar-234731/ (21 Jun 2024)
- TS: https://www.tapsmart.com/apps/deep-dive-arc-search/ (25 Mar 2025, updated 30 Sep 2026; screenshots dated 24 Mar 2025)
- SD: https://screensdesign.com/apps/arc-search-find-it-faster/ (screen library; capture shows content from Oct 2024; only the free preview screens were opened, the Pro-gated ones were not)
- 60FPS: https://60fps.design/apps/arc-search (12 motion shots published 2 Nov 2026; shot pages are https://60fps.design/shots/<slug>)
- WP: https://en.wikipedia.org/wiki/Arc_(web_browser)

---

# A. Version history

## A.0 Coverage summary

| Range | What I found |
|---|---|
| 1.0 (28 Jan 2024) | No vendor notes. Contents reconstructed from launch reviews. |
| 1.0.x to 1.10.x (29 Jan to late Apr 2024) | No per-version notes anywhere I could reach. The help-centre article starts at 1.11.0 and the App Store page only shows the last 25 versions. Only dated milestones from press, vendor videos and one build number in a screenshot. |
| 1.11.0 to 1.30.0 (2 May to 12 Sep 2024) | Vendor notes for 1.11.0, 1.12.0, 1.13.0, 1.14.0, 1.16.0, 1.17.0, 1.18.0, 1.19.0, 1.20.1, 1.21.0, 1.22.2, 1.23.0, 1.24.0, 1.25.0, 1.26.0, 1.27.0, 1.28.0, 1.29.0, 1.30.0. Nothing for 1.15, 1.31, 1.32. |
| 1.33 to 1.39 (Oct to Dec 2024) | Vendor notes for 1.33.0, 1.37.0, 1.38.0, 1.39.0; App Store entries for 1.34.0, 1.34.1, 1.35.0, 1.36.0, 1.37.0, 1.38.0, 1.39.0. Numbering in the two sources does not line up (see A.4). |
| 1.40 to 1.49 (2025 to 2026) | Vendor notes for 1.40.1, 1.40.2, 1.41.0, 1.42.0, 1.43.0, 1.44.1, 1.45.0; App Store entries for every listed version to 1.49.0. No 1.47 in either source. |

## A.1 Launch: 1.0, 28 Jan 2024

Release date 2024-01-28 [ITL]. Announced by Josh Miller as the company's second product, "a default browser for iPhone that browses for you" [X-JM1]. In the same thread he said syncing of Spaces and Pinned Tabs would come to the app when "Arc Anywhere" was finished and that the word "Search" would then be dropped from the name "in the coming month or two" [X-JM2] (the rename never happened; the app is still "Arc Search" [AS]).

What shipped, per launch-week sources:
- Opens to a search field with the keyboard already up [TC1][MR1][GZ][INV]. Stern (lead engineer) says the keyboard appears on opening and on re-opening the app, by design [INV].
- "Browse for Me": reads at least six pages and builds a page [TC1][MR1]. Uses models from OpenAI and others [MR1][TC2].
- Default search engine choices Google, Bing, DuckDuckGo, Ecosia [TC1][MR1].
- Reader mode, find on page, copy URL, share, favorites (star) [MS][TB1].
- Tab switcher in the style of the iOS app switcher; automatic archiving of tabs, default one day, changeable [MS][TC1].
- Always-on blocking of ads, trackers, cookie banners, with per-site switches [GZ][TB1].
- Can be set as the default browser; no account needed [TC1][ATH1].
- Requires iOS 16 [MR1][ITL].
- Lock Screen widget for quick access (reported by one source only) [TB1].
- Missing at launch, per reviewers: iPad layout, Shortcuts actions, widgets (MacStories says none; TidBITS reports a Lock Screen widget two weeks later), sync with desktop Arc, "Paste and Go", renaming or foldering favorites, reading list, downloads, extensions; Browse for Me pages could not be shared [MS][TC1].

## A.2 Between 1.0 and 1.11 (no vendor notes found)

| Date | What changed | Source |
|---|---|---|
| 29 Jan 2024 | An update described only as changing the default search engine options, giving access to archived tabs, and "enhanced haptic feedback". No version number, no detail. | [TR] |
| by 20 Feb 2024 (build shown: "Arc Search 1.2.0 (46583.2)") | Settings footer shows this build. In it: search engine menu lists Browse for Me, Google, Bing, DuckDuckGo, Ecosia, Perplexity, Kagi; incognito toggle in the search field; "Summarize" tile in the page menu; centre button of the bottom bar shows "+" instead of the magnifier of 1.0. | [img ANT-5][img ANT-2][img ANT-3][img ANT-6] |
| 22 Feb 2024 | Incognito mode; Pinch to Summarize; Browse for Me pages can be shared and their links are clickable. The vendor video of that day has chapters "Your #1 request" (content not stated in metadata), "Introducing Incognito", "Pinch to Summarize". Whether this is exactly 1.2.0 is (inferred). | [X-JM3][ALT][TCAT][TB1 reader comment][YT-pfMoRPVtPLg] |
| 26 Mar 2024 | Vendor Short: "a fun, smooth, fresh new update available for arc search today". Content not stated. | https://www.youtube.com/shorts/CoGZf__6ml8 |
| 29 Mar 2024 | Vendor Short: weekly Arc Search update. Content not stated. | https://www.youtube.com/shorts/aT39lzRmDX0 |
| 12 Apr 2024 | Vendor Short titled with "makeover". Content not stated. A third-party video of 18 Apr has chapters "intro screen and onboarding" and "landscape mode", and one of 6 May has "app icon change", so new onboarding, landscape support and alternate app icons arrived somewhere in April to early May (inferred from chapter titles only). A TidBITS reader on 3 May 2024 says landscape "does now" work. | https://www.youtube.com/shorts/7aNokpilSPE ; https://www.youtube.com/watch?v=v2x24L33yHk ; https://www.youtube.com/watch?v=fwFQFnLFJOk ; [TB2] |
| 25 Apr 2024 | Arc Sync: the app syncs Spaces, pinned tabs and Today tabs with desktop Arc; pin from the phone via the search bar or "the computer icon in the tab switcher". Settings by now has "Downloads" and "Archive" buttons, "Global Site Settings", "Set Arc as Default Browser", "Search Engine", "Languages", "Archive Inactive Tabs"; page menu has "Site Settings" and "Problems? Reload without ad blockers". Which of these arrived exactly in this build is not known. | [MACRN][TH][TB2][img ATH3-1][img ATH3-3] |
| 16 May 2024 | The older "Arc Sidebar Sync" app is retired in favour of Arc Search. | [MACRN] |

## A.3 Vendor release notes, 1.11.0 to 1.45.0

Bullets are close paraphrases of the vendor's notes with UI names kept as written [RN].

- **1.11.0, 2 May 2024**
  - "Voice Search": hands-free; hold the plus sign and speak.
  - "New Widget": add from home-screen edit mode; one-tap voice search or synced spaces.
  - "Page Zoom": new tab control, via the up arrow bottom right.
  - "Request Desktop Website": second new tab control, same place.
  - "Improved Gesture Control": smoother swiping from the middle of the page, fewer accidental back swipes.
  - "Redesigned Onboarding Process".
  - Press adds: small and medium widgets; Voice Search is also a Shortcuts action, so it can go on the Action button [9A].
- **1.12.0, 9 May 2024**
  - "Browse for Me Query Editing": edit the query on a Browse for Me page via the up arrow bottom right.
  - "New Browse for Me List Format": list layout for queries where a list fits.
  - "Advanced HTTPS Certificate Bypass": option to continue to a site whose certificate can't be verified.
- **1.13.0, 16 May 2024**
  - "Collapsible Bottom Bar": hides on scroll down, returns on scroll up.
  - "Adjustable % Page Zoom": zoom shows a percentage; tapping it resets to 100%.
  - "Browse For Me Instant Answers": short answers for quick-fact queries (unit conversion, currency).
  - "Ad Blocker Transparency": footer of the Tab Controls shows how many ads and trackers were blocked on the page.
  - "Toggle Keyboard Visibility on App Launch": new setting; the note places it via the up arrow then "Site Settings".
  - "Initial Search Suggestions": starter suggestions for new members after onboarding.
  - "Default Browser Banner": appears after extended use.
- **1.14.0, 23 May 2024**
  - "Call Arc": starts when you hold the phone to your ear and speak. (An App Store listing seen in a search snippet labels this build 1.14.1.)
  - "Auto-Open Keyboard Fixes": the setting applies whether or not tabs are open; the keyboard no longer appears after relaunch or reactivation if turned off. Toggle location: tab switcher (bottom left), then the gear icon for App settings.
  - Press adds: three App Shortcuts "Call", "Search", "Voice Search" [MC1]; home-screen quick action and widget button for Call Arc [ATH4].
- **1.16.0, 6 Jun 2024**
  - Voice-activated search works in any language Siri supports (transcription only in the iOS language).
  - Gesture control reduces accidental "Call Arc" activation.
  - Custom search engines: tab switcher, gear icon, "Search Engine" (the note says "under Site Settings").
  - Long-pressing a link shows a website preview in the popup menu.
  - macOS Handoff offers the current tab's URL to the Mac's default browser.
  - Downloads get sequential numbers so files aren't overwritten.
  - Videos continue in picture-in-picture when you leave the app.
  - Link-sharing action: open links in Arc Search, or run a "Browse for Me" search from selected text.
  - Apple Wallet links with several passes show all passes.
  - Pull-to-refresh waits for release, so dragging back up cancels.
  - Fixed: new tabs opening repeatedly after arc:// links; ad blocker making some links (for example "Visit" on Google Images) unclickable.
- **1.17.0, 13 Jun 2024**
  - "Swipe in the opposite direction to reopen a closed tab."
  - Certain Apple Wallet pass download links now work; fixed downloads that wouldn't open.
- **1.18.0, 20 Jun 2024**
  - "Optimized Arc Search App for iPad": layout suited to iPad screens.
  - Trackers are removed when you share or copy a URL.
- **1.19.0, 27 Jun 2024**
  - Website translation with Google Translate: up arrow, "Translate", then allow once or always.
  - Search results load in the device's preferred language.
  - Basic HTTP authentication dialogs.
  - "Voice Search" button in the search bar.
  - Toggle at the bottom right of search results pages switches between Google and "Browse for Me" results.
- **1.20.1, 4 Jul 2024**: "Browse for Me" now powered by GPT-4o.
- **1.21.0, 11 Jul 2024**: faster app start.
- **1.22.2, 18 Jul 2024** (a search snippet of the App Store shows it as 1.22.0)
  - New "Browse for Me" loading design, with quick query editing from a results page.
  - Text scales to your preferred size in onboarding, "Settings", "Browse for Me" results and search queries.
  - Fixed: LLM entries no longer appear in the "Search Google" tile on "Browse for Me" pages.
- **1.23.0, 25 Jul 2024**
  - Start a "Browse for Me" query from highlighted text.
  - Better host-language parameters for localized results.
  - "Share" removes extra link trackers from Instagram URLs.
  - Downloading .ics files creates calendar events; .mobileconfig installs supported.
  - New onboarding segment on the built-in ad blocker.
- **1.24.0, 1 Aug 2024**
  - Tappable suggested follow-ups in "Browse for Me"; links in "Learn more" add sections to the page.
  - When a site has a native app installed, a banner offers to open the content there. Tapped links no longer open native apps automatically.
  - Fixed: alignment of "Learn more" and "Sources" on iPad; the "Did Arc answer your question" section no longer stays after feedback is sent.
- **1.25.0, 8 Aug 2024**
  - Widget background on or off: touch and hold the widget, "Edit Widget", "Show Background".
  - Choose where links open: Tab Switcher, Settings gear, "Open App Links in...", then "Arc Search" or "Native App".
  - Fixed an iOS 16 crash around universal-link banners.
- **1.26.0, 15 Aug 2024**: behind-the-scenes update.
- **1.27.0, 22 Aug 2024**
  - Shared "Browse for Me" links open the live native page in Arc.
  - Right-to-left language support in "Browse For Me" pages.
  - Fixed: selection handles appearing while scrolling search results.
- **1.28.0, 29 Aug 2024**
  - More detailed "Browse for Me" sections.
  - Onboarding update, with suggested queries in Japanese and Korean.
  - Fixed stray picture frames at the end of some sections.
- **1.29.0, 5 Sep 2024**: performance and feel.
- **1.30.0, 12 Sep 2024**
  - Tips and tricks based on how you use the app.
  - Fixed the misaligned "Ad Blocker" toggle in iPad onboarding.
- **1.33.0, 10 Oct 2024**
  - App icons adapt to iOS 18 dark and tinted styles; browse the custom icons in "Settings".
  - Fixed: Traditional Chinese "Browse For Me" queries getting Simplified Chinese answers.
- **1.37.0, 31 Oct 2024**
  - Universal links open the installed app instead of sending you to the App Store.
  - Clearer voice search guidance for new users.
- **1.38.0, 8 Nov 2024**
  - With cookie blocking on, the app tries to deny cookie consent prompts automatically; if it can't do so reliably, it leaves the prompt alone.
  - Fixed: the earlier cookie blocker sometimes stopped pages from scrolling.
- **1.39.0, 19 Dec 2024**: bug and security fixes; corrected how URLs display in the URL bar.
- **1.40.1, 17 Jan 2025**: fixed "Browse for Me" results sometimes not showing.
- **1.40.2, 30 Jan 2025**: disabled the "Copy URL" button for "Browse For Me" results.
- **1.41.0, 14 Feb 2025**: improved "Browse for Me" results; four iOS security fixes.
- **1.42.0, 10 Mar 2025**: restored access for users with an empty archive; fixed blank pages when refreshing a "Browse 4 Me" search; fixed "Open in App" on some sites including YouTube.
- **1.43.0, 7 Apr 2025**: security improvements and small "Browse For Me" enhancements.
- **1.44.1, 21 Aug 2025**: updated third-party licence acknowledgements, available under "Settings".
- **1.45.0, 7 Oct 2025**: fixed images not showing in "Browse For Me".

## A.4 App Store version history (last 25 entries)

Version numbers and dates below were identical across three reads and are reliable. The note text attached to each row was not: the three reads disagreed by one row about which note belongs to which version in the Oct to Nov 2024 block, so treat the notes column for 1.34.0 to 1.39.0 as "one of these adjacent versions" and prefer A.3 for content. [AS]

| Version | Date | Note (as read) |
|---|---|---|
| 1.49.0 | 19 Oct 2026 | "This update contains bug fixes and security improvements. Happy browsing!" |
| 1.48.0 | 12 Aug 2026 | Same generic text |
| 1.46.1 | 20 Jan 2026 | Same generic text |
| 1.46.0 | 14 Jan 2026 | Same generic text |
| 1.45.2 | 11 Nov 2025 | Same generic text |
| 1.45.1 | 15 Oct 2025 | Fixed images not appearing in Browse For Me results |
| 1.45.0 | 7 Oct 2025 | Same image fix |
| 1.44.3 | 24 Sep 2025 | Fixed an issue when switching from a web search to Browse for Me |
| 1.44.2 | 3 Sep 2025 | Fixed navigation issues affecting certain URLs |
| 1.44.1 | 20 Aug 2025 | Updated third-party licence acknowledgements, viewable in Settings |
| 1.44.0 | 13 Aug 2025 | "Fixed an iOS security issue" (one read gave the 1.43.0 text here) |
| 1.43.0 | 1 Apr 2025 | Tweaked Browse For Me results; four iOS security fixes |
| 1.42.0 | 10 Mar 2025 | Empty archive fix; blank Browse For Me refresh fix; "Open in App" fix (YouTube) |
| 1.41.0 | 17 Feb 2025 | Reads disagree: "disabled the Copy URL button in the navigation bar" for Browse For Me, or the 1.43.0 text |
| 1.40.3 | 2 Feb 2025 | Deprecated sharing of Browse for Me links by disabling the Copy URL button on those pages |
| 1.40.2 | 29 Jan 2025 | Fixed Browse for Me sometimes not showing results |
| 1.40.1 | 17 Jan 2025 | Fixed a bug that sometimes made Browse for Me fail; general code improvements |
| 1.40.0 | 15 Jan 2025 | Bug and security fixes including URL bar display |
| 1.39.0 | 19 Dec 2024 | Bug and security fixes (or the cookie-consent note, depending on the read) |
| 1.38.0 | 8 Nov 2024 | Automatic handling of cookie consent prompts (two reads) |
| 1.37.0 | 31 Oct 2024 | Bug fixes and visual improvements; home-screen widget adapts to the tinted style |
| 1.36.0 | 24 Oct 2024 | App Links open the native app by default when possible, changeable in Settings under "Open App Links in"; visual fixes for iOS 18 |
| 1.35.0 | 17 Oct 2024 | Fixed Call Arc sometimes failing to answer |
| 1.34.1 | 15 Oct 2024 | iOS 18 dark and tinted icons, custom icon choice; a previously rolled-back change re-released; Traditional Chinese fix |
| 1.34.0 | 10 Oct 2024 | Generic text (oldest entry shown) |

Disagreements between RN and AS that I could not resolve: RN calls the 10 Oct 2024 release 1.33.0 where AS shows 1.34.0 on that date; RN dates 1.43.0 to 7 Apr 2025 (AS 1 Apr), 1.41.0 to 14 Feb (AS 17 Feb), 1.40.2 to 30 Jan (AS 29 Jan), 1.44.1 to 21 Aug (AS 20 Aug). A search snippet of a non-US storefront also mentions a "1.33.1" dated 10/04/2024, which is 4 Oct 2024 if day-first (inferred).

## A.5 After the notes stop

- "Call Arc has already been removed from the iOS app" (stated 22 Oct 2026; version not given) [HC].
- An "Export Data" row exists in Settings as of Oct 2026 (Tab Switcher, Settings, "Export Data"); Browse for Me and Incognito tabs are not exported [HC][FAREWELL].
- 23 Nov 2026: Browse for Me and the other AI features turn off; sign-in and sync end. The iOS app keeps working as a browser after 22 Dec 2026 [HC][FAREWELL].
- May 2025: the company put Arc into maintenance mode to focus on Dia [WP].

---

# B. Feature inventory

Each entry: how it is reached, what it does, options. Version tags say when a source shows it.

## Search and launch

1. **Keyboard-first launch.** Opening the app shows the search sheet with the keyboard up and the cursor in the field [TC1][GZ][img MS-1]. Also on re-opening [INV]. Option: a setting controls whether the keyboard appears at launch (1.13.0, fixed in 1.14.0 to apply with or without open tabs) [RN]. Exact label of that setting: not found.
2. **Search sheet.** Reached at launch, by tapping the centre button of the bottom bar ("+" from v1.2; magnifier in v1.0) [img MS-2][img ANT-6], or by swiping up from the bottom [ANT]. Swiping the sheet down dismisses it and reveals the page or tab behind [img ATH3-0][TB2].
3. **Favorites / pinned sites under the field.** With an empty field the sheet lists favorite or recent sites, each with a star at the right (v1.0) [img MS-1][img MS-4]; in synced builds a pin glyph replaces the star [img TB2-1]. Favorites appear in the Search field, can be dragged to reorder, about four show by default [TS].
4. **Suggestions.** Typing replaces the list with search suggestions; each suggestion row has a "Browse for Me" button [MS][img TS-2]. Site matches can appear as rows too (favicon and title) [img ANT-2]. Tapping a suggestion (or "go") runs it in the default search engine in a new tab [MS][TB1].
5. **Scrolling through autocomplete.** "Scroll through auto-complete options": scrolling the suggestion list updates the text in the field to the active suggestion [YT-KRX1EXj6LaI chapter 0:31][60FPS scroll-morph].
6. **Initial search suggestions** for new users after onboarding (1.13.0) [RN]. Onboarding sample queries seen: "things to do in paris", "who are the beatles", "romantic shakespearean reply", "risotto vs paella", "vegetarian dinner ideas" [img SD-3].
7. **Default search engine.** v1.0: Google, Bing, DuckDuckGo, Ecosia [TC1]. v1.2.0 menu, in order: Browse for Me, Google, Bing, DuckDuckGo, Ecosia, Perplexity, Kagi [img ANT-5]. Custom search engines from 1.16.0 [RN]. UI for adding one: not found.
8. **Languages.** A "Languages" row exists in Settings (Apr 2024) [img ATH3-3]; search results load in the device's preferred language from 1.19.0 [RN]. Contents of the Languages screen: not found.
9. **Voice Search.** Hold the "+" button and speak (1.11.0) [RN][9A]; described by the vendor as "Press and hold for walkie-talkie voice search" [YT-KRX1EXj6LaI 1:14]. Also a "Voice Search" button in the search bar from 1.19.0 [RN], a mic button in the Search field [TS], the widget's "Voice" button [img 9A-1], home-screen quick action "Voice Search" [img ATH4-5], and the App Shortcut "Voice Search" / "Voice Search with Arc" [img 9A-2]. First use asks for Microphone and Speech Recognition permission [ATH4].
10. **Call Arc** (1.14.0; removed by Oct 2026 [HC]). With the app open, raise the phone to your ear and ask [X-NP][RN]. Hold music plays while it searches, then a spoken answer; you can ask follow-ups [MR2][TC2][MC1]. Controls "Speaker", "End", "Read More" ("Read More" opens the full Browse for Me result) [MR2][img TS-4]. Tap the waveform above the controls to interrupt [ATH4]. Other entry points: home-screen quick action "Call Arc", widget, App Shortcut "Call" / "Call Arc" [ATH4][img 9A-2]. A switch for it exists in Settings, reported as "Raise to Call" [TS] (a search snippet of a forum post words it "Raise to call Arc"; exact label unconfirmed). 1.16.0 made accidental activation less likely and added all Siri languages [RN].

## Browse for Me

11. **Starting it.** Tap "Browse for Me" on a suggestion row [MS][img TS-2]; set "Browse for Me" as the default search engine (v1.2.0 menu) [img ANT-5]; from highlighted text on a page (1.23.0) or through the link-sharing action (1.16.0) [RN]; Shortcuts [MC2].
12. **Loading screen.** v1.0: dark screen with three lines: the query; "Reading 6 web pages" followed by the list of domains; "Making a website for you" [img TC1-1]. Redesigned in 1.22.2 with quick query editing [RN]. A late recording is described as a full-screen pulsing gradient with a progress line and a staggered list of source URLs [60FPS ai-generation-loader].
13. **Result page.** See C.6. Sections over time: image/video carousel, title, emoji key points, source cards, sub-sections, "Dive Deeper" (v1.0) [ATH2][img MS-6]; list format (1.12.0), instant answers (1.13.0), follow-ups and "Learn more" / "Sources" (1.24.0), "Did Arc answer your question" feedback section, a "Search Google" tile [RN].
14. **Toggle between Browse for Me and the search engine.** Floating two-segment control at the bottom right of result pages (1.19.0) [RN][img TS-1].
15. **Query editing** from the result page (1.12.0, via the up arrow; redesigned 1.22.2) [RN].
16. **Sharing.** Not possible at launch [TC1]; shareable links from 22 Feb 2024, opening in any browser [ALT][ANT]; shared links open the live native page in Arc (1.27.0) [RN]; sharing deprecated and the Copy URL button disabled on these pages in 1.40.2 / 1.40.3 [RN][AS].
17. **Language handling.** Right-to-left support (1.27.0); answers follow language preference (1.33.0) [RN].

## Page view

18. **Bottom bar.** Three controls: tab stack (left), search/new (centre), up arrow (right) [MS][img MS-2]. No address bar in the collapsed bar [MS].
19. **Collapsible bottom bar** (1.13.0): hides on scroll down, returns on scroll up [RN]. Per-site switch "Collapse Bottom Bar" in Site Settings [img SD-10].
20. **Swipe on the bottom bar.** "Swipe left and right on the bottom bar to cycle between recent tabs" [YT-KRX1EXj6LaI 0:16]. In v1.0 MacStories describes flicking up on the thumbnails at the left of the bar to toggle between the current and previous page [MS].
21. **Swipe to navigate.** Swipe right for back, left for forward in the tab's history; "Swipe to Navigate" option with value "From Anywhere" (the alternative restricts it to screen edges; its label was not seen) [TB1][img ANT-4]. Swiping back on the first page of a tab archives the tab and returns to the previous tab [TB1]. Swiping the opposite way reopens a closed tab (1.17.0) [RN]. Onboarding copy: "Swipe anywhere to go back" [img SD-2].
22. **Pull to refresh**, cancellable by dragging back up (1.16.0) [RN].
23. **Page menu (up arrow).** See C.4. Long-pressing the up arrow opens the share sheet directly (v1.0) [MS].
24. **Reader.** Tile in the page menu, "Reader Mode" in 1.0, "Reader" from 1.2 [img MS-1][img ANT-4]. Reader UI itself: not found.
25. **Find on Page.** Tile in 1.0, row from 1.2 [img MS-1][img ANT-4]. Its bar UI: not found.
26. **Copy link.** "Copy URL" tile in 1.0, "Copy Link" from 1.2 [img MS-1][img ANT-4]. Trackers are stripped when sharing or copying (1.18.0) [RN]. In late builds a link glyph sits inside the address pill and the vendor calls it the "Copy URL button in the navigation bar" [img SD-10][AS].
27. **Share.** Tile in the page menu [img ANT-4]; Instagram tracker removal (1.23.0) [RN].
28. **Page Zoom** (1.11.0) with minus and plus; percentage display, tap to reset to 100% (1.13.0) [RN][img 9A-1].
29. **Request Desktop Site** (1.11.0) [RN][img 9A-1].
30. **Translate** (1.19.0): page menu, "Translate", allow once or always; uses Google Translate [RN]. A Google Translate permission modal exists [SD].
31. **Pinch to Summarize.** Pinch in on a page as if zooming out; the page folds down and a summary appears [X-JM3][ALT]. Also the "Summarize" tile in the page menu [img ANT-4]. Per-site switch "Pinch to Summarize" [img SD-10]. Summary has copy and share buttons in late builds [SD].
32. **Ad, tracker and cookie-banner blocking.** On by default; per-site switches "Block Ads", "Block Cookie Banners", "Block Trackers" and global defaults [img ANT-4][img TB1-5][img SD-10]. Page menu footer "Problems?" with "Reload without ad blockers" (Apr 2024) [img ATH3-4]. Count of blocked ads and trackers in the menu footer (1.13.0) [RN]. A tracker-blocked notification appears on article pages in late builds [SD]. Cookie prompts are auto-denied from 1.38.0 [RN].
33. **Link long-press.** Shows a website preview in the popup menu (1.16.0) [RN]. Menu items: not found.
34. **Text selection.** Start a Browse for Me query from highlighted text (1.23.0) [RN].
35. **Native app banners / App Links.** Banner to open in the native app (1.24.0); setting "Open App Links in..." with "Arc Search" and "Native App" (1.25.0); native by default (1.36.0) [RN][AS].
36. **Downloads.** "Downloads" button in Settings (Apr 2024) [img ATH3-3]; numbered duplicates (1.16.0); Wallet passes, .ics, .mobileconfig handling [RN]. Downloads list UI: not found.
37. **Picture-in-picture** continues when leaving the app (1.16.0) [RN].
38. **HTTP basic auth dialogs** (1.19.0) and **invalid-certificate bypass** (1.12.0) [RN]. A "hostname not found" error screen exists [SD].
39. **Handoff** to the Mac (1.16.0) [RN].
40. **Passwords.** Onboarding says "Passwords carry over from Safari" [img SD-2]; MacStories noted 1Password autofill sometimes failing in 1.0 [MS].

## Tabs

41. **Tab switcher.** Tap the tab stack at bottom left [MS]; TechCrunch also describes "swipe and hold from the left edge" [TC1]. Cards like the iOS app switcher, oldest left, newest right; swipe a card up to close (archive) it [MS][TB1].
42. **Auto-archive.** "Archive Inactive Tabs": 12 hours, 1 day, 3 days, 7 days, 30 days [img ANT-5]; default 1 day [TC1][img ATH3-3]. No "never" option was seen.
43. **Archive.** v1.0: button at the bottom centre of the tab switcher [img MS-5]; from Apr 2024: Settings, "Archive" [img ATH3-3][TS]. Searchable; grouped by day, then longer periods; "Edit" mode; swipe to delete; tapping an entry reopens it on top of the stack [img MS-5][TB1][SD].
44. **Incognito.** Toggle at the right of the search field (two-eyes glyph) [img ANT-2]. Tapping it switches the current tab to incognito [TS]. Incognito tabs do not appear in the tab switcher and are excluded from history [TS] and from Export Data [HC].
45. **Clear Browsing Data.** Settings row; sheet "Clear Data" with "Clear History" and "Clear Cookies and Site Data" switches and a "Clear" button [img ANT-7].
46. **Export Data** (Oct 2026): Tab Switcher, Settings, "Export Data"; shares or copies a list of open tabs [HC].

## Sync with desktop Arc (ends 23 Nov 2026)

47. **Sign in.** Tab switcher, monitor icon at bottom left, "Sign in with Arc" [ATH3][TB2]. After sign-in a tooltip reads "Welcome <name>" / "Tap here to browse your spaces" [img ATH3-2].
48. **Spaces view.** Monitor icon in the tab switcher. Shows the desktop sidebar per Space (pinned tabs, folders, Today tabs); swipe left and right between Spaces; tap an item to open it as an Arc Search tab [TB2][ATH3][img TB2-1]. Favorites, Profiles and History don't sync [ATH3]. Tabs opened in Arc Search don't sync back to the desktop (help-centre text seen only in a search snippet).
49. **Pin from the phone.** Page menu, pin glyph in the address pill; menu "Favorite in App", "Pin to Space:" and the list of Spaces, "Pin to Folder…" [img ATH3-5]. To unpin, tap the pin glyph and deselect [ATH3]. Pins made on the phone show a small mobile icon in the desktop sidebar and land at the bottom of the pinned section [TB2][ATH3].
50. **Share extension "Arc Search".** From any app's share sheet; shows a "Saved" screen with a destination picker (remembers the last place) and "Done"; swipe down to dismiss without saving [TB2][img TB2-3].
51. **Widget "Spaces" button** opens synced Spaces [img 9A-1].

## System integration

52. **Default browser.** Offered in onboarding and from Settings ("Set Arc as Default Browser" in Apr 2024; "DEFAULT BROWSER / Open Settings" in v1.2.0) [img ATH3-3][img ANT-5]; a banner after extended use (1.13.0) [RN].
53. **Widgets.** Small and medium Home Screen widgets (1.11.0) [9A]. Medium: logo, "Search" field, "Voice" and "Spaces" buttons [img 9A-1]; a "Call Arc" button from 1.14 [ATH4]. "Edit Widget", "Show Background" (1.25.0); adapts to iOS 18 tint (1.37.0) [RN][AS]. Lock Screen widget reported in Feb 2024 [TB1]. An in-app widget tutorial exists [60FPS add-widget-animation].
54. **App Shortcuts / Shortcuts.** "Call" ("Call Arc"), "Search" ("Search with Arc"), "Voice Search" ("Voice Search with Arc"); usable from Siri, Spotlight, the Action button [MC1][img 9A-2][img TS-5].
55. **Home-screen quick actions.** "Change App Icon", "Call Arc", "Voice Search", "Search" (Jun 2024) [img ATH4-5].
56. **App icons.** Nine choices in onboarding (late 2024) [img SD-7]; dark and tinted variants for iOS 18 (1.33.0 / 1.34.1) [RN][AS]. An in-app picker is described as a glass "dock" in a bottom sheet that scrolls horizontally [60FPS app-icon-dock-picker].
57. **Landscape.** Works by early May 2024 [TB2].
58. **Dynamic Type** in onboarding, Settings, Browse for Me results and search queries (1.22.2) [RN].
59. **Tips** based on usage (1.30.0) [RN]. A rating prompt exists [SD].
60. **Easter egg.** The logo on the empty home screen spins like a fidget spinner when flicked [ITL][YT-KRX1EXj6LaI 1:40][60FPS fidget-spinner].
61. **"Gift Arc".** Row in the page menu (v1.0 to at least May 2024) [img MS-1][img 9A-1]. What it opens: not found.

## iPad

62. **iPad layout** (1.18.0, 20 Jun 2024). Before that the iPad ran the iPhone app [TB2]. The vendor called it a version with "all your favorite features", adapted for the larger screen, with a tablet-native redesign only a hope for later [MC3]. Browse for Me works in Split View [IFUN]. See C.14.

---

# C. Screen by screen

Version drift is large; each screen lists the newest evidence first, then how older builds differed.

## C.1 Launch / search screen

Newest evidence (Mar 2025) [img TS-2], with details from 2024 images:
- Background: when no tab is open, a full-screen gradient (deep blue to purple to red/pink in the marketing render; a dark variant appears in Feb 2024 screenshots) with the Arc Search logo centred [img ITL-1][img ANT-2][img ANT-4]. When a tab is open the page or tab card shows dimmed behind the sheet [img TS-2][img ATH3-0].
- A sheet with large rounded top corners rises from the bottom and sits directly on top of the keyboard [img MS-1][img TS-2].
- Inside, top: a full-width capsule text field. Placeholder "Search..." [img MS-1][img ANT-2][img ITL-1]. Cursor blue.
- Right end of the empty field: the incognito toggle, a two-eyes glyph (from v1.2) [img ANT-2][img ATH3-0]. When text is present a round clear button (x) sits there instead [img TS-2]. A "Voice Search" / mic button is in the search bar from 1.19.0 [RN][TS]; its exact position was not seen in any image I could open.
- Below the field: rows. Empty state: favorites/recent sites, each = favicon, title, trailing star (1.0) or pin glyph (synced builds) [img MS-1][img TB2-1]. First-run: sample queries with "Browse for Me" buttons [img ITL-1].
- Keyboard: standard iOS keyboard; return key reads "go" (blue when there is text) [img TS-2].

## C.2 Suggestions list

[img TS-2] (Mar 2025):
- Each row: magnifier icon, suggestion text (wraps to two lines), trailing "Browse for Me" capsule button. The typed prefix is grey and the completed remainder is dark.
- The first row repeats the typed query as-is.
- Four rows fit above the keyboard on the phone shown.
- Feb 2024 [img ANT-2]: mixed list, site rows (favicon and title, no button) above and below a query row (magnifier, text, "Browse for Me").
- Marketing render: the first row's "Browse for Me" is filled blue, the others grey [img ITL-1].

## C.3 Web page view and bottom bar

- Page content runs full height; no top bar and no visible URL [img MS-2][MS].
- Bottom bar, translucent, three items [img MS-2][img ANT-6][img TS-1]:
  - Left: a small fanned stack of two tab thumbnails (live miniatures of recent pages). Tap = tab switcher.
  - Centre: a wide grey capsule. Icon: magnifier in 1.0 [img MS-2], "+" from 1.2 onward [img ANT-6][img TS-1]. Tap = search sheet; hold = voice search [RN].
  - Right: a circle with an up chevron. Tap = page menu; hold = share sheet (1.0) [MS].
- The bar collapses on scroll (1.13.0) [RN].
- On Browse for Me and search-result pages a floating two-segment toggle sits above the bar at the right [img TS-1].

## C.4 The page menu (the up-arrow sheet; the vendor calls it "Tab Controls")

Newest full image is 2 May 2024 (v1.11) [img 9A-1]; later changes are listed after it.

A sheet with rounded top corners, bottom of screen, over the dimmed page. Top to bottom:
1. Address capsule: back chevron, forward chevron, the domain (centred, for example "disneytouristblog.com"), pin glyph, reload glyph.
2. Four square tiles with a label under each: "Reader", "Summarize", "Copy Link", "Share".
3. A grouped list: "Find on Page"; "Page Zoom" with a minus | plus stepper at the right; "Request Desktop Site"; "Site Settings".
4. A separate single row: "Gift Arc".
5. Footer line: "Problems?" followed by a small capsule button "Reload without ad blockers".

Differences by build:
- v1.0 (Jan 2024): capsule has a star instead of the pin; tiles are "Reader Mode", "Find on Page", "Copy URL", "Share"; below them two capsule buttons side by side, "Gift Arc" and "Settings" [img MS-1][img TB1-5].
- v1.2.0 (Feb 2024): tiles "Reader", "Summarize", "Copy Link", "Share"; then a "Find on Page" row; then a group "Gift Arc", "Settings" [img ANT-4].
- Late Apr 2024: as v1.11 but without Page Zoom and Request Desktop Site: "Find on Page"; group "Gift Arc", "Site Settings"; footer "Problems?" "Reload without ad blockers" [img ATH3-4][img TB2-3].
- Added later, per notes: zoom percentage that resets on tap, blocked ads/trackers count in the footer (1.13.0), "Translate" (1.19.0) [RN]. Exact position of "Translate": not found.
- Late 2024: the capsule shows a link glyph where the pin was in a signed-out session (back, forward, "nba.com", link glyph, reload) [img SD-10]; the vendor refers to a "Copy URL button in the navigation bar" [AS].
- Mar 2025 text description lists "Summarize", "Find in Page", "Pin", "Favorite in App", "Site Settings" [TS] (no image; "Find in Page" may be the writer's wording).
- Pin menu (popover from the pin glyph, Apr 2024) [img ATH3-5]: "Favorite in App" (phone glyph); section header "Pin to Space:"; one row per Space with its icon at the right; "Pin to Folder…" with a disclosure chevron at the left and a folder glyph at the right.
- Whether "Gift Arc" still exists in 1.4x: not found.

## C.5 Tab switcher

- Full-screen, soft gradient background (light lavender/pink in light mode) [img MS-5][img ATH3-2].
- Cards: tall rounded page snapshots, overlapping horizontally like the iOS app switcher; above each card its favicon and title (truncated) [img MS-5][img ATH3-2]. Newest at the right [MS]. Swipe up to close [MS][TB1][TS].
- Bottom controls:
  - v1.0: a single round archive (box) button at bottom centre [img MS-5].
  - From Apr 2024: left = round monitor icon (Spaces / sign-in); centre = "+" capsule; right = round gear (Settings) [img ATH3-2][img TB2-1]. Still so in the current App Store render [img ITL-ipad8].
- Incognito tabs are not shown here [TS].
- Empty state, "close all", tab count, reordering: not found.

## C.6 Browse for Me result page

Mar 2025 [img TS-1], consistent with late 2024 [img SD-9]:
1. A white capsule at the top: magnifier icon and the query text (for example "best places to visit paris france"). Tapping it to edit is (inferred) from "quickly edit your query from a results page" [RN]. A share glyph at its right appears in the onboarding mock [img SD-4] but not in the Mar 2025 screenshot, matching the removal of sharing in 1.40.x.
2. Image collage: one large image and a column of two smaller ones, continuing horizontally.
3. A row of source favicons followed by "Read 11 web pages" and an up chevron (collapsible).
4. A horizontally scrolling row of source cards: two-line title, then favicon and domain.
5. Title in large blue type (for example "Top Places to Visit in Paris").
6. Key points: an emoji at the left, then bold term, an em dash, and the text.
7. Further sections with blue headings and the same bullet style; inline links underlined [img ITL-ipad2]; a "Search Google" tile can lead the card row [img ITL-ipad2][RN]; "Learn more", "Sources", follow-up chips, a video carousel and a "Did Arc answer your question" block exist per notes and the screen library [RN][SD].
8. Floating at bottom right: two-segment capsule, left = Arc/Browse-for-Me glyph on a purple gradient (selected), right = the search engine's "G".
9. Bottom bar as on any page.

v1.0 layout (Jan 2024) [img MS-6][ATH2]: image carousel, centred blue title with a small squiggle divider, emoji key points, blue sub-headings, a "From ign.com" disclosure line under a section, a block quote, and a final "Dive Deeper" list (favicon, title, domain).

## C.7 Summary view (Pinch to Summarize / "Summarize")

Mar 2025 [img TS-3], same structure as Feb 2024 [img ANT-1]:
- Soft gradient background.
- Top: favicon and page title on one line; under it the page as a card, folded: a thin strip above the card shows the top of the page mirrored upside-down (the fold).
- Summary paragraph in regular text.
- Sections: a round blue icon, a bold title, body text.
- Fixed footer: Arc Search icon, "Summarized for you by Arc Search", and a round close (x) button at the right.
- Copy and share buttons are reported for late builds [SD]; not visible in the images I opened.

## C.8 Voice search and Call Arc

Voice search overlay [img 9A-1][img ITL-7]:
- The page dims and blurs; a glow in blue, purple and pink rises from the bottom.
- A white smiley (two vertical bars for eyes, a curved mouth).
- Text "Hi! How can I help?" at rest; while speaking, a caption capsule shows the live transcript.
- A dotted waveform at the bottom.

Call Arc screen [img TS-4][img TC2-1]:
- Full-screen gradient (blue, purple, red).
- Top: call timer ("0:40"), then "Arc" in large type, then the smiley.
- A white speech bubble with two small thought dots holds the current line. First-run greeting in the vendor's render: "Hi! I'm Arc. You can reach me to ask questions on the go by raising your phone to your ear. What would you like to know?" [img TC2-1]. A later recording shows "What's up?" [60FPS raise-to-call-arc].
- A capsule with a dotted waveform (tap to interrupt [ATH4]).
- Three round buttons with labels: "Speaker", "End" (red), "Read More".

## C.9 Spaces view and saving

- Spaces sheet [img TB2-1]: a full-height sheet tinted with the Space's colour; Space name at top left; round close (x) at top right; a list of rows (favicon or folder glyph, title); at the bottom a row of Space icons for switching; swipe sideways between Spaces [TB2].
- "Saved" screen from the share extension [img TB2-3]: gradient sheet; a white heart with a check; "Saved"; a capsule picker showing the destination's icon and name with up/down chevrons; a wide "Done" button.

## C.10 Settings

No source shows the complete Settings screen of a 1.4x build. What is documented, newest first:

**Site Settings sheet** (page menu, "Site Settings"; late 2024) [img SD-10]. Title "Site Settings", "Done" at top right, grabber at the top. In order:
1. Section header "<DOMAIN> SETTINGS" (for example "NBA.COM SETTINGS")
   - "Block Ads" (switch; red icon with a hand)
   - "Block Cookie Banners" (switch; orange cookie icon)
   - "Block Trackers" (switch; yellow sunglasses icon)
2. Second group
   - "Pinch to Summarize" (switch)
   - "Collapse Bottom Bar" (switch)
   - "Swipe to Navigate" (value "From Anywhere")
3. "App Settings" (disclosure)

**App Settings** (tab switcher gear, or Site Settings then "App Settings"). Top of the screen in Apr 2024 [img ATH3-3], in order:
1. Title "Settings", "Done"
2. Two capsule buttons side by side: "Downloads", "Archive"
3. "Global Site Settings" (disclosure)
4. "Set Arc as Default Browser" (disclosure)
5. "Search Engine" (value "Google") and "Languages" (one group)
6. "Archive Inactive Tabs" (value "After 1 day")
7. Rows below were cut off in the image.

Rows known to exist in later builds without a known position or exact label: the keyboard-at-launch switch (1.13/1.14) [RN]; the Call Arc switch ("Raise to Call") [TS]; "Open App Links in..." with "Arc Search" / "Native App" (1.25.0) [RN]; custom app icons (1.33.0) [RN]; third-party licence acknowledgements (1.44.1) [RN]; "Clear Browsing Data" [HC]; "Export Data" (Oct 2026) [HC]; sign-in to Arc / account [SD]. A 2026 tutorial reaches "Clear Browsing Data" by scrolling down in App Settings (https://www.youtube.com/watch?v=0mg1UgzYmnQ).

**Settings in v1.2.0** (Feb 2024) [img ANT-4][img ANT-5][img ANT-7], complete, in order:
1. "Default Site Settings" (disclosure): "Block Ads", "Block Cookie Banners", "Block Trackers" switches; "Swipe to Navigate" = "From Anywhere"
2. "Default Search Engine" (value "Google"; menu: Browse for Me, Google, Bing, DuckDuckGo, Ecosia, Perplexity, Kagi)
3. Header "DEFAULT BROWSER": "Open Settings"; footer "Set as Default Browser to open links from other apps in Arc Search."
4. "Archive Inactive Tabs" (value "After 30 days"; menu: 12 hours, 1 day, 3 days, 7 days, 30 days); "Clear Browsing Data..."
5. "Contact the Team"; "Privacy Policy"; "Show Onboarding"
6. Footer "Arc Search 1.2.0 (46583.2)"

In v1.0 the Settings sheet opened from the page menu and began with the current site's section ("<DOMAIN> SETTINGS" with the three block switches and "Swipe to Navigate"), then "Default Site Settings", then "Default Search Engine" [img TB1-5].

**Clear Data sheet** [img ANT-7]: title "Clear Data", close (x); "Clear History" (switch); "Clear Cookies and Site Data" (switch); wide blue "Clear" button.

## C.11 Archive

[img MS-5] (v1.0): sheet with "Edit" (left), "Archive" (title), "Done" (right); a search field "Search"; sections "TODAY", "YESTERDAY", then older; rows = favicon, title, and the URL as subtitle; Browse for Me entries show the query as title and "Browse for Me" as subtitle. Later builds: date groupings and swipe-to-delete [SD]. Empty state: not found.

## C.12 Incognito

[img ANT-2]: the same search sheet in a dark theme; the field shows "Search..." with "Incognito" and a filled eyes glyph at the right; centred below, "You're browsing Incognito". The keyboard switches to its dark variant [60FPS incognito-toggle]. How an incognito page differs from a normal page (bar tint, badge): not found.

## C.13 Onboarding (late 2024 build) [SD]

1. Gradient screen, logo at the top, "Get what you want twice as fast.", button "Next" [img SD-1].
2. "Meet your new favorite browser" with four cards: "Protect your privacy" / "Arc blocks all creepy trackers"; "Auto-archives old tabs" / "No more virtual dust bunnies"; "Keep your logins" / "Passwords carry over from Safari"; "Navigate faster" / "Swipe anywhere to go back". "Next" [img SD-2].
3. "Let Arc search and summarize for you": a phone mock with "Try it!" and an arrow to a highlighted "Browse for Me" on the first of five sample queries [img SD-3].
4. A check mark and a Browse for Me result mock; "Next" [img SD-4].
5. "Pinch to summarize any web page" with "Skip" at top right and two finger dots on a mock page [img SD-5].
6. A check mark and the summary mock; "Skip", "Next" [img SD-6].
7. "Pick an icon for your home screen": 3 by 3 grid with radio marks; choosing one raises the system alert "You have changed the icon for “Arc Search”." / "OK"; "Next" [img SD-7][img SD-8].
8. "Get what you need, without the noise": a row "Block Ads and Trackers" with a switch, button "Let’s go" [img SD-11].
9. Default-browser prompt with a primary button and a skip option [SD] (labels not seen in this build).

Launch build (Jan 2024): first screen had a "Let's go" button [SG][ATH1]; then the default-browser screen with "Set as Default Browser" and "Skip"; "Skip" asks "Are you sure?" with "Seriously, skip for now!" [GZ].

## C.14 iPad layout

- Page view: the same three-item bottom bar stretched across the width, tab stack at far left, "+" capsule centred, up-arrow circle at far right; no sidebar, no top bar (19 Jun 2024 photo) [img IFUN-1].
- Browse for Me: content in a centred reading-width column; toggle floating at bottom right [img ITL-ipad2].
- Tab switcher: landscape-shaped cards; monitor icon at bottom left, "+" centred [img ITL-ipad8].
- Split View supported [IFUN]. Stage Manager, keyboard shortcuts, pointer behaviour, a sidebar: not found in any source.

---

# D. Verbatim strings

All read directly from images unless marked (reported), which means an article's wording. In on-screen order within each group.

**Search sheet**
- "Search..." (placeholder; rendered with three dots or an ellipsis glyph, not distinguishable) [img MS-1][img ANT-2][img ITL-1]
- "Browse for Me" (button on suggestion rows) [img ANT-2][img TS-2]
- "Incognito" (label beside the eyes glyph) ; "You're browsing Incognito" [img ANT-2]
- "go" (keyboard return key) [img TS-2]

**Bottom bar**: icons only.

**Page menu, v1.11 (May 2024)** [img 9A-1]
- "Reader" ; "Summarize" ; "Copy Link" ; "Share"
- "Find on Page" ; "Page Zoom" ; "Request Desktop Site" ; "Site Settings"
- "Gift Arc"
- "Problems?" ; "Reload without ad blockers"

**Page menu, v1.0** [img MS-1]: "Reader Mode" ; "Find on Page" ; "Copy URL" ; "Share" ; "Gift Arc" ; "Settings"

**Page menu, later additions (reported)**: "Translate" [RN] ; "Pin" [TS]

**Pin menu** [img ATH3-5]: "Favorite in App" ; "Pin to Space:" ; "Pin to Folder…"

**Site Settings (late 2024)** [img SD-10]: "Site Settings" ; "Done" ; "NBA.COM SETTINGS" (pattern: domain in capitals + " SETTINGS") ; "Block Ads" ; "Block Cookie Banners" ; "Block Trackers" ; "Pinch to Summarize" ; "Collapse Bottom Bar" ; "Swipe to Navigate" ; "From Anywhere" ; "App Settings"

**App Settings (Apr 2024, top part)** [img ATH3-3]: "Settings" ; "Done" ; "Downloads" ; "Archive" ; "Global Site Settings" ; "Set Arc as Default Browser" ; "Search Engine" ; "Google" ; "Languages" ; "Archive Inactive Tabs" ; "After 1 day"

**App Settings (reported, position unknown)**: "Open App Links in..." ; "Arc Search" ; "Native App" [RN] ; "Raise to Call" [TS] ; "Clear Browsing Data" ; "Export Data" [HC]

**Settings, v1.2.0** [img ANT-4][img ANT-5][img ANT-7]: "Settings" ; "Done" ; "Default Site Settings" ; "Default Search Engine" ; "DEFAULT BROWSER" ; "Open Settings" ; "Set as Default Browser to open links from other apps in Arc Search." ; "Archive Inactive Tabs" ; "After 30 days" ; "Clear Browsing Data..." ; "Contact the Team" ; "Privacy Policy" ; "Show Onboarding" ; "Arc Search 1.2.0 (46583.2)"
- Search engine menu: "Browse for Me" ; "Google" ; "Bing" ; "DuckDuckGo" ; "Ecosia" ; "Perplexity" ; "Kagi"
- Archive menu: "12 hours" ; "1 day" ; "3 days" ; "7 days" ; "30 days"
- Default Site Settings: back button "Settings" ; title "Default Site Settings" ; "Block Ads" ; "Block Cookie Banners" ; "Block Trackers" ; "Swipe to Navigate" ; "From Anywhere"

**Clear Data sheet** [img ANT-7]: "Clear Data" ; "Clear History" ; "Clear Cookies and Site Data" ; "Clear"

**Archive** [img MS-5]: "Edit" ; "Archive" ; "Done" ; "Search" ; "TODAY" ; "YESTERDAY" ; "Browse for Me" (row subtitle)

**Browse for Me**
- Loading, v1.0 [img TC1-1]: "Reading 6 web pages" ; "Making a website for you"
- Result page: "Read 11 web pages" (number varies: 10, 11, 13 seen) [img TS-1][img SD-9][img SD-4] ; "Search Google" (tile) [img ITL-ipad2] ; "Dive Deeper" (v1.0 section) [img MS-6] ; "From ign.com" (pattern "From <domain>", v1.0) [img MS-6]
- (reported) "Learn more" ; "Sources" ; "Did Arc answer your question" [RN]

**Summary** [img TS-3][img ANT-1]: "Summarized for you by Arc Search"

**Voice search** [img 9A-1]: "Hi! How can I help?"

**Call Arc** [img TS-4][img TC2-1]: "Arc" ; "Speaker" ; "End" ; "Read More" ; "Hi! I'm Arc. You can reach me to ask questions on the go by raising your phone to your ear. What would you like to know?" ; (reported) "What's up?" [60FPS]

**Sync** [img ATH3-2][img TB2-3]: "Welcome <first name>" ; "Tap here to browse your spaces" ; "Saved" ; "Done" ; (reported) "Sign in with Arc" [ATH3][TB2]

**Onboarding (late 2024)** [img SD-1..11]: "Get what you want twice as fast." ; "Next" ; "Meet your new favorite browser" ; "Protect your privacy" ; "Arc blocks all creepy trackers" ; "Auto-archives old tabs" ; "No more virtual dust bunnies" ; "Keep your logins" ; "Passwords carry over from Safari" ; "Navigate faster" ; "Swipe anywhere to go back" ; "Let Arc search and summarize for you" ; "Try it!" ; "Pinch to summarize any web page" ; "Skip" ; "Pick an icon for your home screen" ; "You have changed the icon for “Arc Search”." ; "OK" ; "Get what you need, without the noise" ; "Block Ads and Trackers" ; "Let’s go"

**Onboarding (Jan 2024, reported)**: "Let's go" / "Let's Go" [SG][ATH1] ; "Set as Default Browser" ; "Skip" ; "Are you sure?" ; "Seriously, skip for now!" [GZ]

**Widget** [img 9A-1]: gallery title "Arc Search", subtitle "Open Arc Search" ; field "Search" ; buttons "Voice", "Spaces" ; (reported) "Call Arc" [ATH4] ; "Edit Widget" ; "Show Background" [RN]

**App Shortcuts / Spotlight / quick actions** [img 9A-2][img TS-5][img ATH4-5]: "Call Arc" ; "Search" ; "Voice Search" ; "Voice Search with Arc" ; "Search with Arc" ; quick actions "Change App Icon", "Call Arc", "Voice Search", "Search"

**App Store captions (current listing)** [img ITL-1][img ITL-5][img ITL-7][img ITL-ipad2][img ITL-ipad8]: "Fastest way to search. Cleanest way to browse." ; "Say goodbye to pop-ups and ads." ; "Search with your voice when your hands aren’t free." ; "Generate the perfect answer to any question with Browse for Me." ; "Seamlessly sync your browsing across all your devices."

Empty-state texts (no tabs, empty archive, empty downloads), error texts, permission prompt wording, tooltip/tip texts: not found.

---

# E. Motion, gestures, haptics

Statements from sources; none of the videos were watched, so timings are absent unless a source gave them. No source gives a duration, spring constant or curve for anything.

Gestures
- Pinch in on a page: summary [X-JM3]. Pinch tutorial in onboarding simulates two fingers [img SD-5].
- Swipe right / left on a page: back / forward, "From Anywhere" or edges only [TB1][img ANT-4]. Smoother swiping from the middle of the page from 1.11.0 [RN].
- Swipe back on a tab's first page: archives the tab and shows the previous tab [TB1]. Swipe the other way: reopens the closed tab (1.17.0) [RN].
- Swipe left/right on the bottom bar: cycle recent tabs [YT-KRX1EXj6LaI]. v1.0: flick up on the thumbnails to toggle current/previous page (can collide with the Home indicator) [MS].
- Swipe up from the bottom (or tap "+"): new search [ANT].
- Swipe the search sheet down: dismiss [TB2][img ATH3-0].
- Swipe a tab card up in the switcher: close/archive [MS][TB1].
- Swipe sideways in the Spaces sheet: change Space [TB2].
- Swipe-to-delete in Archive [SD].
- Hold "+": voice search [RN]. Hold the up arrow: share sheet [MS]. Long-press a link: preview and menu [RN].
- Raise to ear: Call Arc [X-NP].
- Pull to refresh fires on release; dragging back cancels [RN].
- Flick the logo: fidget spinner [60FPS].
- Scroll the suggestion list: field text follows [60FPS].

Animations (descriptions are from the 60fps.design shot pages unless tagged otherwise)
- Pinch to Summarize: the page "folds down (origami-style)" [X-JM3]; shrinks to a small thumbnail [TCAT]; folds "with an animation and haptic feedback" [ALT].
- Summarize from the menu: the page shrinks into a floating card over a dark magenta gradient; the card wiggles while a loading message shows; when ready the card moves to the top and summary blocks and icons rise from the bottom with a light spring settle [60FPS summarize-interaction].
- Browse for Me loading: keyboard dismisses; full-screen gradient of deep blues, purples and magentas that morphs and pulses; a progress line fades in ("reading six web pages"), then a staggered list of source URLs that scroll and fade; on completion the gradient fades and result cards slide up [60FPS ai-generation-loader].
- Suggestion scroll morph: the shared prefix of the query stays still while the changing suffix morphs, crossfades and slides [60FPS scroll-morph].
- Incognito toggle: background crossfades to deep grey, keyboard switches to dark, the icon springs into place, placeholder and "You're browsing Incognito" fade in [60FPS incognito-toggle].
- Voice search (long press): page dims and blurs; a full-screen overlay scales up and fades in with a glowing gradient, the smiley and an animated waveform; "bouncy, elastic easing" [60FPS long-press-assistant].
- Call Arc: full-screen blue-to-red gradient; speech bubble springs in with a bounce; vertical bars pulse with sound [60FPS raise-to-call-arc]. The smiley's mouth moves while the answer plays [TC2].
- Fidget spinner: spins fast, slows gradually, settles upright with a small springy bounce [60FPS fidget-spinner].
- Onboarding: tapping the primary button shifts the background gradient from saturated blues and reds to a pale gradient; text slides up and fades in with a slight stagger; the button changes label and style [60FPS gradient-transition]. On the splash, the smiley mascot winks: the left eye squashes down and pops back [60FPS intro-splash-wink]. Pinch tip: card collapses with spring, a check badge pops in, "Next" slides up [60FPS pinch-to-summarize-tip].
- App icon picker: a glass dock in a bottom sheet; icons slide across it on horizontal swipe [60FPS app-icon-dock-picker].
- Tab switcher: MacStories calls the animations "fluid and fast" and Safari's noticeably slower, with a side-by-side video in the review [MS].
- Fluted-glass material was designed before launch and cut because it did not hold up over arbitrary web pages [INV].

Haptics
- "Enhanced haptic feedback" in the 29 Jan 2024 update, no detail [TR].
- Haptic feedback during the pinch fold [ALT].
- Nothing else found. (Android notes mention haptics on voice recognition, which says nothing about iOS [ANDRN].)

Audio
- Call Arc plays hold music while searching [MR2][MC1][TS].

---

# F. Visual references

Videos were located and their metadata checked, not watched. "Screen recording" is inferred from titles, descriptions and chapters unless stated. YouTube metadata was read through a reader proxy (r.jina.ai) and X posts through api.fxtwitter.com.

## F.1 Best video references

Vendor (channel https://www.youtube.com/@TheBrowserCompany)
- https://www.youtube.com/watch?v=KRX1EXj6LaI (23 Jul 2024, 2:15) "Our favorite (not-so-obvious) features in Arc Search". 0:16 swipe the bottom bar to cycle recent tabs; 0:31 scroll through autocomplete; 0:43 widget; 0:58 pin links; 1:14 press-and-hold voice search; 1:40 fidget-spinner logo.
- https://www.youtube.com/watch?v=3ctHrOz1uY0 (25 Apr 2024, 7:36) "Arc Everywhere: Set up Arc Sync across iOS, Windows, and Mac": sign-in, Spaces, pinned and Today tabs on iPhone. No chapters.
- https://www.youtube.com/watch?v=1DKo86wPmQg (25 Apr 2024, 2:38) Arc Sync for iOS release video.
- https://www.youtube.com/watch?v=pfMoRPVtPLg (22 Feb 2024, 4:34) 0:30 Arc Search updates; 0:38 "Your #1 request"; 1:13 Incognito; 1:33 Pinch to Summarize.
- https://www.youtube.com/watch?v=1eiRhBRVt_s (23 May 2024, 0:32) "Call Arc: For questions on the go".
- https://www.youtube.com/watch?v=FHA5YZEAYOc (15 Aug 2024, 1:00) overview.
- Shorts: https://www.youtube.com/shorts/4uE9UgeGEVw (29 Jan 2024, launch); https://www.youtube.com/shorts/4doIOracZmI (22 Feb 2024, pinch); https://www.youtube.com/shorts/CoGZf__6ml8 (26 Mar 2024); https://www.youtube.com/shorts/aT39lzRmDX0 (29 Mar 2024); https://www.youtube.com/shorts/7aNokpilSPE (12 Apr 2024); https://www.youtube.com/shorts/tdqK2m5yVjo (18 Apr 2024); https://www.youtube.com/shorts/-PgJFpLu7-w (2 May 2024, voice search).

Vendor and staff posts with direct MP4s
- Launch video, vertical, 57 s: https://twitter.com/browsercompany/status/1751968818283315212 ; MP4 https://video.twimg.com/ext_tw_video/1751967885725962240/pu/vid/avc1/720x1560/eYiitvpEL5Jk6lc5.mp4?tag=12
- Launch GIFs: https://twitter.com/joshm/status/1751734580124787028 (https://video.twimg.com/tweet_video/GE9NVjnbgAAD3V1.mp4) ; Browse for Me https://twitter.com/joshm/status/1751735179004244339 (https://video.twimg.com/tweet_video/GE9pYfMbUAAsmbY.mp4)
- Pinch fold, 15 s: https://twitter.com/joshm/status/1760698068943724634 ; MP4 https://video.twimg.com/amplify_video/1760698009351016448/vid/avc1/444x960/NLPg9yddj54Y7ZxB.mp4?tag=14
- Call Arc demo by its designer, 73 s: https://twitter.com/nateparrott/status/1793643577605796307 ; MP4 https://video.twimg.com/ext_tw_video/1793638959127400449/pu/vid/avc1/1280x720/cwiS-c9HLEo_iELY.mp4?tag=12
- Third-party pinch clips: https://x.com/raywongy/status/1760778395309277302 (31 s; https://video.twimg.com/ext_tw_video/1760778348299423744/pu/vid/avc1/720x1280/7neV2KHau-1od37u.mp4?tag=12) ; https://x.com/ParkerOrtolani/status/1760691721086583251 (8 s) ; https://x.com/Jake_Joseph/status/1760749989779718168 (8 s)
- Call Arc GIF: https://techcrunch.com/wp-content/uploads/2024/05/call-arc.gif

Motion libraries
- https://60fps.design/apps/arc-search : 12 recorded clips (gradient transition on button tap, pinch tip, add widget, app icon dock picker, scroll morph, incognito toggle, raise to Call Arc, intro splash wink, AI generation loader, summarize interaction, fidget spinner, long press assistant). Media URLs are not in the page text; some may need a subscription.
- https://screensdesign.com/apps/arc-search-find-it-faster/ : a 7:13 recording of a late-2024 build. Chapters: 0:00 welcome; 0:04 feature showcase; 0:07 Browse for Me demo; 0:24 pinch demo; 0:33 app icon selection; 0:42 ad-blocking; 0:50 default browser prompt; 0:55 AI search; 2:03 browsing and page interaction; 6:08 settings. Most of it is behind a paid tier. This is the only source I found that shows the full App Settings of a late build.
- https://www.youtube.com/watch?v=dnvoLv1Exf0 (Andy Matuschak, 1 Aug 2024, 1:57:33) rebuilds the pinch fold in Origami; 0:00 to 4:41 analyses the real interaction.

Third-party walkthroughs
- https://www.youtube.com/watch?v=0mg1UgzYmnQ (Tube Raw, 9 Feb 2026, 1:36): a late build. 0:30 up arrow then Site Settings; 0:42 App Settings; 0:52 Clear Browsing Data; 1:05 choices; 1:15 Clear.
- https://www.youtube.com/watch?v=Ak0nct40H94 (Tech Gully, 29 Aug 2026, 6:03): tabs, auto-archive, pinned tabs, summaries.
- https://www.youtube.com/watch?v=gwm9d5Nt-Zk (28 Feb 2024, 11:45, Japanese): 2:39 opens to search; 3:06 Browse for Me; 4:49 tab view; 5:43 summary; 7:03 blocking; 7:35 gestures.
- https://www.youtube.com/watch?v=v2x24L33yHk (18 Apr 2024): 4:07 intro and onboarding; 5:07 Browse for Me; 6:04 pinch; 6:33 landscape.
- https://www.youtube.com/watch?v=fwFQFnLFJOk (6 May 2024): 0:35 app icon change; 1:59 sync; 4:00 widget.
- https://www.youtube.com/watch?v=qxLaa_gf21A (10 Jun 2024, 8:33): 0:15 Browse for Me; 2:56 summary; 3:39 Call Arc; 5:17 widget; 5:48 sync; 7:46 reader.
- https://www.youtube.com/watch?v=-9Pw62MEdfA (29 Jan 2024, 9:17): launch build; 2:07 search; 3:24 Browse for Me; 7:17 Settings.
- https://www.youtube.com/watch?v=djczFuVHEdQ (26 Feb 2024, 3:32): 0:17 quick search; 0:42 Browse for Me; 1:28 share; 2:12 Settings.
- https://www.youtube.com/watch?v=3pHSHyBAH2U (8 Mar 2025, 7:04, Japanese): 1:54 pinch; 2:56 Browse for Me; 3:59 switching between AI and Google results.
- iPad: https://www.youtube.com/watch?v=chsrZsik2fI (29 Jun 2024, 7:03), the only iPad hands-on found.
- Recent vertical: https://www.youtube.com/shorts/jLVCwYsjgps (29 Apr 2026).

## F.2 Pages with real screenshots, and direct image URLs

I opened every image listed with an `img` key. Keys used in the text above:

- MS (v1.0, 29 Jan 2024)
  - MS-1 https://cdn.macstories.net/monday-29-jan-2024-02-16-35-1706490999694.png (tab switcher, page menu, search sheet)
  - MS-2 https://cdn.macstories.net/monday-29-jan-2024-02-22-53-1706491377955.png (Safari vs Arc Search bottom bars)
  - MS-4 https://cdn.macstories.net/monday-29-jan-2024-02-24-05-1706491450152.png (favorites in the search sheet)
  - MS-5 https://cdn.macstories.net/monday-29-jan-2024-02-27-08-1706491632482.png (tab switcher with archive button; Archive sheet)
  - MS-6 https://cdn.macstories.net/monday-29-jan-2024-01-24-33-1706487891442.png (Browse for Me page, three parts)
  - not opened: https://cdn.macstories.net/monday-29-jan-2024-02-20-53-1706491257230.png , https://cdn.macstories.net/monday-29-jan-2024-02-29-30-1706491775028.png
- ANT (v1.2.0, Feb 2024), base https://storage.ghost.io/c/79/45/794539e9-2a02-4255-8c35-d208fe7cbac5/content/images/2024/02/
  - ANT-1 Arc-Search-Page-Summerizer.jpeg ; ANT-2 Arch-Search-Incognito-Mode.jpeg ; ANT-4 Arc-Search-Ad-blocking.jpeg (page menu, Settings, Default Site Settings) ; ANT-5 Arc-Search-default-search-engine-and-archive-time.jpeg ; ANT-6 Arc-Search-Quick-Search-2.jpeg ; ANT-7 Clearing-Browsing-History-in-Arc-Search.jpeg
  - not opened: Arc-Search-Quick-Search.jpeg , Arc-Search-Browse-for-me-feature.jpeg , Arc-Search-Browse-for-me-feature-in-action.jpeg , Arc-Search-Tab-Switcher.jpeg , Arc-Search-Fine-on-Page.jpeg (find on page; worth opening)
- TB1 (Feb 2024): TB1-5 https://tidbits.com/wp/../uploads/2024/02/Arc-Search-options-settings-scaled.jpg ; not opened: .../Arc-Search-tab-switcher-scaled.jpg , .../Arc-Search-archived-tab-list-scaled.jpg , .../Arc-Search-Google-scaled.jpg , .../Arc-Search-Browser-For-Me-restaurant-scaled.jpg
- TB2 (Apr 2024): TB2-1 https://tidbits.com/wp/../uploads/2024/04/Arc-Search-tabs-scaled.jpg (search sheet, page, tab switcher, Spaces sheet) ; TB2-3 https://tidbits.com/wp/../uploads/2024/04/Arc-Search-saving-scaled.jpg (page menu, Saved screen) ; not opened: .../Arc-Search-Arc-Sync-scaled.jpg , .../Arc-Search-share-sheet-scaled.jpg
- ATH3 (Apr 2024), base https://static.allthings.how/content/images/2024/04/ : ATH3-0 IMG_4955.PNG (search sheet) ; ATH3-2 IMG_4959.PNG (tab switcher with welcome tooltip) ; ATH3-3 IMG_4971.PNG (Settings top) ; ATH3-4 IMG_4965.PNG (page menu) ; ATH3-5 IMG_4966.PNG (pin menu) ; not opened: IMG_4954, IMG_4953, IMG_4952, IMG_4960, IMG_4961, IMG_4963, IMG_4967, IMG_4969 (.PNG)
- ATH4 (Jun 2024), base https://static.allthings.how/content/images/2024/06/ : ATH4-5 IMG_5627.PNG (quick actions) ; not opened: IMG_5618, IMG_5624, IMG_5626, IMG_5619-1, IMG_5628, IMG_5629 (.PNG; Call Arc flow and widget)
- 9A (2 May 2024): 9A-1 https://9to5mac.com/wp-content/uploads/sites/6/2024/05/Untitled-2.jpg (page menu, voice search, widget) ; 9A-2 https://9to5mac.com/wp-content/uploads/sites/6/2024/05/Thursday-02-May-2024-10_54_50.jpg (Shortcuts, Action button)
- TC1-1 https://techcrunch.com/wp-content/uploads/2024/01/Arc-search-process.jpeg (Browse for Me loading, v1.0) ; not opened: https://techcrunch.com/wp-content/uploads/2024/01/Arc-Search-result-page.jpeg , https://techcrunch.com/wp-content/uploads/2024/02/IMG_4374.jpeg
- TC2-1 https://techcrunch.com/wp-content/uploads/2024/05/arc-search-call.png (vendor render of Call Arc)
- IFUN-1 https://images.ifun.de/wp-content/uploads/2024/06/arc-ipad-app-scaled.jpg (iPad page view) ; not opened: .../browse-for-me-scaled.jpg (Browse for Me in Split View), .../arc-browser-ansicht-scaled.jpg
- TS (24 Mar 2025), base https://www.tapsmart.com/wp-content/uploads/2025/03/ : TS-1 arc-search-browse-for-me-page.png ; TS-2 arc-search-browse-for-me.png (suggestions) ; TS-3 arc-search-in-page-summary.png ; TS-4 arc-search-call.png ; TS-5 arc-search-spotlight.png
- SD (late 2024), base https://media.screensdesign.com/avs-pp-640/ : SD-1 099707a5faec4fb2b1c9038cf20aad80.webp ; SD-2 5bb7db77b8474996a8eca7ae559a8929.webp ; SD-3 2fcb4d8a87ec4f0da9412b36fb2e04e4.webp ; SD-4 b9b0d71f95284007b2a1b9035545dcc8.webp ; SD-5 f377116e65fd452aad139985b3eb2f30.webp ; SD-6 3194847773794e0fa07bcd4a88489c75.webp ; SD-7 d04f6d0721a64f4b88dc1d3b0af53bcd.webp ; SD-8 cd701f3084524ff791bc7352033aaa7c.webp ; SD-9 861e2add18e1466083592e3b40e1a48a.webp (Browse for Me page) ; SD-10 021577faaca64347a099bcd67b44fd02.webp (Site Settings) ; SD-11 1dbdb5ae7e3645949510dbdf73179194.webp ; not opened: a47ed06a1f59463a98535ec6159c881a.webp (splash)
- ITL (current App Store renders; change the size suffix as needed)
  - ITL-1 https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/03/c0/a5/03c0a52e-aae6-e4fe-2102-94798914fe45/42412753-d9ff-451d-90e6-26290963cf92_iphone_5.5_-_01.jpg/600x1066bb.jpg
  - ITL-5 https://is1-ssl.mzstatic.com/image/thumb/PurpleSource211/v4/b9/b8/d1/b9b8d1ff-b2ec-fffc-c079-8c3beeb04cac/794947f2-8d21-4f03-9d6d-67a5cd9e4c23_iphone_5.5_-_05.jpg/600x1066bb.jpg
  - ITL-7 https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/04/2b/03/042b03e4-9bbf-6904-4c5f-7dbfb06644ac/7c3784db-8a65-40b8-8b48-f71a51f78e86_iphone_5.5_-_07.jpg/600x1066bb.jpg
  - ITL-ipad2 https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/5a/9a/be/5a9abe5a-feba-b3b9-4167-b9b540c38774/e087a1b5-4f8f-44f4-8032-604d42c47f51_ipad_12.9__screenshot_-_02.jpg/1104x828bb.jpg
  - ITL-ipad8 https://is1-ssl.mzstatic.com/image/thumb/PurpleSource221/v4/7b/ea/da/7beadadf-f5b3-9a4c-f147-53bef93a28e3/ed53ad46-128d-47c3-817b-4cc381b66604_ipad_12.9__screenshot_-_08.jpg/1104x828bb.jpg
  - The other seven iPhone and eight iPad screenshot URLs are in the ITL response and were not opened.
- Not opened, likely useful: GZ images https://i.gzn.jp/img/2024/01/30/arc-search-review/IMG_0019.png (default-browser onboarding), IMG_0022.png ("Are you sure?"), IMG_0033.png (Browse for Me loading), IMG_0066.png to IMG_0069.png (menu and Settings); ATH1 images https://static.allthings.how/content/images/2024/01/IMG_3800.PNG and IMG_3801.PNG (first-run screens); ATH2 images https://static.allthings.how/content/images/2024/01/IMG_6692-1.PNG , IMG_6696-1-1.PNG , IMG_6694-1.PNG; TCAT https://storage.ghost.io/c/2a/1b/2a1b1782-8506-4d7d-bf53-ad3fb52e2a0f/content/images/2024/02/IMG_1789.PNG (incognito); MR2 https://images.macrumors.com/t/2-v8WQAxrkuq6v0OZhq3BEserO0=/400x0/article-new/2024/05/arc-search-voice-search.jpg?lossy
- Screen libraries without readable image URLs: https://www.banani.co/references/apps/arc-search (16 screens: onboarding 5, browsing 8, tabs overview 3; dated 22 Oct 2026); https://www.spottedinprod.com/apps/arcsearch

---

# G. Open questions

Things sources disagree on
1. **Label drift in the page menu.** "Reader Mode" / "Copy URL" (Jan 2024) became "Reader" / "Copy Link" (Feb 2024 on) in screenshots, yet the vendor's 2025 notes still say "Copy URL button". TapSmart (2025) writes "Find in Page" where every screenshot I have says "Find on Page". No screenshot of the page menu newer than May 2024 was readable, so its final order and labels (and where "Translate" sits, whether "Gift Arc" survives, how the blocked-count footer reads) are unconfirmed.
2. **Where settings live.** v1.0 to 1.2: one "Settings" sheet from the page menu. Apr 2024 on: "Site Settings" from the page menu and app settings from the tab switcher gear. The vendor's own notes place the keyboard switch under "Site Settings" (1.13.0), then under the gear's "App settings" (1.14.0), and "Search Engine" "under Site Settings" via the gear (1.16.0). "Default Site Settings" (Feb 2024) vs "Global Site Settings" (Apr 2024); "Default Search Engine" vs "Search Engine".
3. **Call Arc switch label.** "Raise to Call" [TS] vs "Raise to call Arc" (search snippet). And since Call Arc was removed from iOS by Oct 2026 [HC], whether the row, the widget button, the quick action and the App Shortcut were removed with it is unknown. Voice Search's status after the AI shutdown is also unstated.
4. **Version numbers and dates.** RN vs AS (see A.4). Which App Store note belongs to which of 1.34.0 to 1.39.0 could not be pinned down. 1.14.0 vs 1.14.1 and 1.22.2 vs 1.22.0 between RN and App Store snippets.
5. **How many pages Browse for Me reads.** "At least six" at launch; 10, 11 and 13 in later screenshots. The rule is not documented.
6. **Opening the tab switcher by gesture.** TechCrunch: "swipe and hold from the left edge". TidBITS: swiping right is back, and on the first page archives the tab. MacStories: flick up on the thumbnails. The vendor (Jul 2024): swipe left/right on the bottom bar cycles recent tabs. These may describe different builds.
7. **Call Arc greeting.** "Hi! I'm Arc. You can reach me..." (vendor render, first run) vs "What's up?" (later recording). Voice search: "Hi! How can I help?".
8. **Launch widgets.** MacStories says no widgets at launch; TidBITS (15 Feb 2024) mentions a Lock Screen widget; vendor notes introduce the Home Screen widget in 1.11.0.
9. **Android general availability date** is inconsistent inside Wikipedia (Nov 2024 vs Nov 2025); the vendor's notes say 14 Nov 2024. Not relevant to iOS behaviour.

Things I could not confirm
- Per-version changes for 1.0.x to 1.10.x, 1.15, 1.31, 1.32, 1.47; what "Your #1 request" was in the 22 Feb 2024 video; contents of the 26 Mar, 29 Mar, 12 Apr and 18 Apr 2024 updates.
- The complete App Settings screen of any 1.4x build: full row list, order, section headers, icons, footers, the account/sign-in block, licences screen, "Contact the Team" / "Privacy Policy" / "Show Onboarding" still present or not, exact label of the keyboard-at-launch switch and of the app-icon row.
- Languages screen; custom search engine editor; Downloads list; Reader view (controls, themes, fonts); Find on Page bar; Translate prompt wording; link long-press menu items; image long-press menu; text-selection menu wording for Browse for Me; HTTP auth dialog; certificate warning page and its bypass wording; native-app banner wording; default-browser banner wording; tips wording; rating prompt.
- Tab switcher details in late builds: empty state, any close-all action, card sizes, whether pinned/favorite tabs appear, how the Browse for Me cards look.
- Incognito page chrome (how a private tab differs once a page is open), and whether incognito has its own tab stack.
- Edge-only value label for "Swipe to Navigate".
- Dark-mode appearance of most screens (only the search sheet and Browse for Me loading were seen dark).
- Any timing, easing or haptic type. Sources describe motion in words only.
- iPad specifics beyond three images: keyboard shortcuts, pointer support, multiwindow, sheet presentation (popover vs sheet), landscape vs portrait differences.
- Accessibility (VoiceOver labels), localisation (the App Store lists English only [AS]).
- What the UI looks like after 23 Nov 2026 once Browse for Me, summaries and sync are switched off (which buttons disappear).
- The Verge's coverage (launch review, Call Arc, sync) and r/ArcBrowser threads: both sites were unreachable with the tools allowed here. The Wayback Machine, which would hold the deleted help-centre feature articles and older App Store version histories (1.0 to 1.33), was also unreachable. Those three are the most promising places to close the gaps above, along with the paid tier of the screensdesign recording and simply watching the videos in F.1.
