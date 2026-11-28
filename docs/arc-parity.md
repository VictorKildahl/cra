# Arc parity sweep (Arc 1.172.1, 7 Nov 2026)

A full pass over Arc's menu bar, Settings window, Shortcuts list, right-click menus and Library,
compared item by item with Cra on main (8dbd6d1). Arc was an offline copy on a fake home
(docs/arc-reverse-engineering.md, "One space"), read through Accessibility and window captures.
Arc's source file list (paths left in its binary) was used to find feature modules Cra has no
counterpart for.

Status: **missing** = Cra has nothing; **partial** = Cra has some of it; **done** = built in this
sweep (commit noted). Items marked *skip* are left out on purpose (cloud, account, AI partner,
or Arc-only service), per CONTRIBUTING.md.

## 1. Whole features

| Arc feature | Where in Arc | Cra | Notes |
|---|---|---|---|
| Boosts (per-site CSS/JS, colours, fonts, Zap) | URL bar ✎, Library ▸ Boosts, Settings ▸ Advanced "Enable Boosts" | done | New Boost (command bar), the editor (wheel, invert, contrast/brightness/saturation, 20 fonts, size, case, Zap with its confirm popover and the shelf of zapped elements under the page (click one to unzap; "Zap, measured" below), CSS/JS code), Library ▸ Boosts, Settings ▸ Advanced switch. The Code panel's eyedropper (selector picker: outlines the element and the ones like it, then Copy selector for this / for related, Zap all related elements), hammer (Show / Hide Developer Tools) and, for JS, Refresh this Page. Sharing and the gallery are Cra's own, look only (no JS): Library ▸ Boosts and the editor's menu have Share Boost… (a crabrowser.app/boost link carrying the boost), and crabrowser.app/boosts lists `boosts/` with Open in Cra (`cra-boost:`, asked about first; `SharedBoost`, boosts/README.md). The colour wheel's tint leaves images alone as in Arc (#602): on the Chromium engine it is Arc's own colorize (measured 21 Nov 2026: lightness kept in a band, light colours at the big handle's hue and dark ones at the small handle's) that the engine paints into text, backgrounds and borders but not into images (`Boost.tint`, cra-boost-tint.patch); WebKit tabs still use a CSS filter, close but not Arc's. |
| Easels | File ▸ New Easel ⌃⇧E, Library ▸ Easels | done | File ▸ New Easel (⌃⇧E): canvas, title, Pointer/Image/Text/Ellipse/Rectangle/Arrow/Freehand, pictures by file, paste or drop, saved per easel. Library ▸ Easels and Window ▸ View Easels… done. The canvas shows the window's backdrop under a 50 % veil as in Arc. The toolbar strip above it takes the same veil. The capture menu's New Easel and Send To… done. The pill's + and − and Aa (Arc's four looks: bold, serif, wide, mono, in macOS's designs) work, on the title too; Duplicate (the toolbar's eighth button) done. Gaps closed 11 Nov (Arc 1.172.2, item by item below, "Easels, item by item"): Arc's filled shapes in its Vibrant/Chill palettes, the colour picker over a picked shape, a click placing a 200 pt shape, the object menu (Bring to Front, Send to Back, Delete, Cut, Copy, Paste, Duplicate), the canvas menu (Paste, Color Palette, Use Alignment Guides) and the guides, Undo/Redo, link cards from a pasted or dropped address or a dropped sidebar tab, captures that keep their page and can show it live, alt text and the easel's thumbnail. Sharing is done without a server (Share Easel…, a `crabrowser.app/easel#…` link that carries the easel; see "Sharing" in Easels, item by item). Arc's embedded browsers and rich text, which nothing in 1.172.2 creates, and Export as web pages are *skip* (Arc winding down; Cra's easels are already files on the Mac). |
| Notes | File ▸ New Note ⌃⇧N, ⌃⌥N in split, Help ▸ Export Arc Notes | *skip* | Arc 1.172.1 no longer creates Notes: New Note is gone from the File menu and ⌃⇧N does nothing; only Help ▸ Export Arc Notes is left. |
| Library ▸ Media | Window ▸ View Media…, Library rail | done | Off until Show Media; right-click the rail's Media button for the folders (Cra has no captures folder). A pick opens Arc's preview over the dimmed window (see "Library, measured"); the Library stays open. |
| Screenshots in the downloads list | Library button: the hover list and its badge (`HomeBadging`, Arc 1.174.2) | done | A screenshot or screen recording the system takes (⇧⌘3, ⇧⌘4, ⇧⌘5) shows up by itself in the list hovering the Library button opens, among the downloads by date, for a day: drag it onto a page or into another app, click to open it, right-click for Open, Copy, Show in Finder, Hide from Cra, Move to Trash. Like Arc, only files carrying macOS's screen-capture mark (`kMDItemIsScreenCapture`), not the folder's other pictures; Cra finds them through Spotlight, live, so nothing reads the Desktop to list them and a launch asks macOS for nothing (#757). Library ▸ Media's Show Media doesn't hold it back; unticking Screenshots in the Media button's "Show media" menu does (Arc's source preference). Spotlight leaves out, without asking, files macOS doesn't let Cra read: with the screenshot folder on the Desktop (the system's default), Cra reads that folder the first time the Library is opened in a launch, so macOS asks for Desktop access then, once, as Arc's Library did; granted, the Desktop's screenshots join the list from then on. A screenshot folder elsewhere (Pictures, a folder of its own) needs nothing. Arc's badge on the button itself is not built (`ScreenshotFeed`, `ScreenshotWatcher`; scenarios `downloads-tray-screenshots`, `downloads-tray-screenshots-off`). |
| Essential Keyboard Shortcuts window | Help ▸ Essential Keyboard Shortcuts, Settings ▸ Shortcuts | done | 475×462 floating dark panel, five rows of key caps, "View All ↗". |
| Appearance | View ▸ Appearance ▸ Automatic / Light / Dark ("Websites, Easels, and Notes will use:"); command bar "Switch to Light Mode" / "Switch to Dark Mode" / "Switch to Automatic Appearance" | done | Forces prefers-color-scheme for pages and, as in Arc, the browser's own appearance: windows, menus, command bar, Auto space themes (#362). Light or Dark there is Arc's one appearance setting (the theme editor's sun and moon): every space's sidebar takes its material, a space's own Light or Dark included, and keeps its colours; Automatic gives each space its own back (#700, scenario `appearance-every-space`). |
| Stay On Top | Window ▸ Stay On Top | done | Floats the window above other apps. |
| Save Page As | File ▸ Save Page As ⇧⌘S | done | |
| File menu: Share…, New Profile, Arc's sections | File ▸ Share…, File ▸ New Profile | done | GitHub #279: the File menu has Arc 1.172.1's five sections and rows (FileMenu); Share… opens the system share list under the toolbar, New Profile the New Profile dialog; Close Tab shows only with a tab selected; New Space… moved to Spaces, New Folder… to Tabs. |
| Tabs menu: Arc's rows and groups, extras kept as shortcuts | Tabs | done | GitHub #622: the visible menu has Arc 1.173.1's three groups. Cra's additional actions stay available through hidden shortcut rows, Settings ▸ Shortcuts, the command bar and tab menus. Rows are dimmed when choosing them would do nothing; unlike Arc, Next and Previous are dimmed in a fully empty space or with one tab (a deviation Victor approved, 20 Nov 2026). |
| Capture Full Page / Portrait Mode | File, URL-bar menu | done | Portrait: 390 × 844 pt at 3x. |
| Capture | File ▸ Capture… ⇧⌘2, Site Control Center camera | done | Arc's mode: grey page, lens, click or drag, Copy / Save… / Send via iMessage… / Retake / New Easel (CaptureOverlay). A click takes Arc's choice (its score, from the binary). Cra's own, not in Arc: holding ⌥ takes the element right under the pointer instead, a title line, a button, inside open shadow roots too (GitHub #451, Victor 16 Nov 2026, `ContentCapture.choose`). |
| Copy URL without trackers | Copy URL ⇧⌘C ("Copy the current tab's URL without trackers") | done | utm_* and click ids dropped (CleanURL). |
| Menu on several picked tabs | ⌘/⇧-click tabs, right-click one | done | Arc 1.17x's rows, read over AX (PickedTabsMenu, #356): Copy Links, Share N Items… \| Change Icon… (dimmed), Mute \| Open in Split View (dimmed past four), Duplicate, Move to ▸ (spaces, New Space…), New Folder with N Items \| Archive Tabs (pinned picks too), Archive Tabs Below (dimmed, Today rows only); with an Easel among the picks the short menu ending in Archive Items. Share asks first with Arc's "Send this Folder to anyone, on any browser." sheet (AppDialog.shareLink), as Share Folder… now does. |
| Pinned extension's menu | Right-click a pinned extension (toolbar or sidebar) | done | GitHub #695, from the reporter's Arc 1.17x capture (Chromium's extension action menu): the name (opens the Web Store page for a Web Store extension), the extension's own action items (1Password's Settings, Lock, Save ▸, Help ▸), the site access line ("This Can Read and Change Site Data" ▸ When You Click the Extension, On <site>, On All Sites, Learn More; or "Can't Read or Change Site's Data", greyed out: `ExtensionSiteAccess`, engine 159.0.8154.45-7), Options with an options page, Remove from Cra, Unpin, Manage Extension, View Web Permissions (`ExtensionActionMenu`); Cra's icon choices (Original Icon, Monochrome, Symbol, Choose Image…) under Icon. Scenarios `toolbar-extension-menu`, `extension-menu-own-items`, `extension-site-access`. |
| Copy URL as Quote | Edit ▸ ⌃⇧⌘C, "Enable Shared Quotes when highlighting text" | done | Arc links to arc.net (cloud); Cra copies a text-fragment link. |
| Paste and Go | Edit ▸ ⌥⌘V | done | Arc 2023's "paste clipboard as new tab", which Arc dropped in March 2024; kept on Victor's call (#610). A copied link opens as a new tab, other text is searched; in a text field it pastes. Cra takes the key before the page (`PasteAndGo`, scenario `paste-and-go`). |
| AppleScript dictionary | Arc.sdef, View ▸ Developer ▸ Allow JavaScript from Apple Events | done | Arc's terms and codes (resources/Cra.sdef); `execute javascript` only after View ▸ Developer ▸ Allow JavaScript from Apple Events (off by default, as in Arc). `make new window`, incognito with `{incognito:true}` (#427). `tabs of window` lists every space's tabs like Arc, the open space first so `tab 3` is still ⌘3 (#428). Cra's own, not in Arc (#438): `pause media [only …] [except …] [profile "…"] [closing picture in picture …]`, the command bar's Pause All Media for scripts, answering `{paused:n, kept playing:{titles}}`; and a space's `profile` (its profile's name). |
| Cast | View ▸ Cast | done | Chrome's Cast bubble (IDC_ROUTE_MEDIA). A sidebar tab's menu has Cast… after Mute on web pages, which Arc's doesn't: it shows the tab and opens the dialog for it (X DM 22 Nov 2026, Victor's call; scenario tab-menu-cast). |
| Shared tab marks | A call sharing a tab (Meet's Present a tab) | done | X DM 19 Nov 2026, from a recording of Arc 1.173: 2 pt systemYellow ring on the shared tab's row and its page card; hovering another tab shows "Share this tab instead" (rectangle.inset.filled.and.person.filled, 24 pt, against ✕), which switches the call and shows that tab (TabSharing, engine -33, page-shared-tab-marks). Arc's tab menu has no Cast row (Cast is View ▸ Cast); Cra's has one (see Cast). |
| Recording dot | A tab using the camera or microphone | done | ARCUI.RecordingDotIndicator, leading the row (TabCellView.hasLeadingRecordingIndicator): a 7 pt systemRed dot where the favicon would start, the favicon 14 pt in, pulsing toward white and back (0.75 s each way, still under Reduce Motion). Measured from the same Arc 1.173 recording (RecordingDot, recording-dot). Cra had a still dot at the row's end. |
| Page translation | Toolbar `character.bubble`, URL field "Translation Available", popover | done | GitHub #310: Arc's button (left of the sliders), the URL field's line with the toolbar hidden, the popover (Options: Choose Another Language ▸, Never Translate This Site, Language Settings; Translate / Show Original) and its toasts, on Chromium's translate state instead of Chrome's bubble (scripts/cef-patches/translate-ui.patch). Never Translate This Site uses Chromium's per-profile list, not Arc's `translateNeverHosts`; Settings ▸ Advanced ▸ "Reset Translated-site Prompts" (GitHub #373) forgets the sites and the languages always or never to translate (Arc's `translateNeverHosts` and `translateSourceLanguagesAlwaysOrNever`) in every profile, each put back to Chromium's default as `TranslatePrefs::ResetToDefaults` does (`TranslateReset`); a profile not loaded that session has its Preferences file reset. |
| Find and Replace, Use Selection to Find, Jump to Selection | Edit ▸ Find | done | Use Selection to Find and Jump to Selection (⌘J) done. *skip*: Find and Replace (⌥⌘F). Checked live in Arc 1.172.2 on 11 Nov: it does nothing anywhere Cra has a counterpart. In an Easel text box with the caret in it, the whole Find submenu is off and ⌥⌘F does nothing; on a web page Find… is on but Find and Replace stays off. It was for Notes, which Arc 1.172 no longer has. |
| Link preview | Hovering a link, bottom left over the page | done | GitHub #689, from the reporter's Arc screenshots and recording (2x): a black capsule 24 pt tall and fully round, a 1 pt border at white 20 %, 12 pt medium text in grey 175 with 10 pt each side, the address without its scheme or the slash ending its path. Holding ⇧, ⌥ or ⌘ says what a click will do: "Open <the whole address, white> in Peek / in Split View / in a new tab", following what Cra does with that click (`LinkPreview`; no Peek line with Shift-click Peek off or in incognito). Scenario `link-preview-arc` with snapshots. Arc's find bar (⌘F) is left as Cra's: the reporter preferred it, and it is Ask on Page's card (#393). |
| Sound effects | Settings ▸ Advanced "Play Arc sound effects" | done | Settings ▸ Advanced ▸ Play Cra sound effects gates the capture shutter. |
| Theme data for websites | Settings ▸ Advanced "Allow websites to get your theme data" | done | `--arc-palette-*` and `--arc-background-*` as #RRGGBBAA, from the space's theme (ArcThemeData; fitted to Arc's stored palette, checked live). |
| Window dragging from the top of webpages | Settings ▸ Advanced | done | An ordinary-arrow drag that starts within 60 pt of the card's top, its bar included, moves the window: the top 60 pt of the page with the toolbar hidden, 28 pt under the toolbar (Arc measured side by side, #363). Text, link and resize cursors keep their gesture; the rightmost 14 pt stay with the page and its scrollbar. The press reaches the page immediately, the first drag event moves the window, and the page gets the release, so a slipped click still clicks (WindowContentGrabber, PageTopDrag). Settings ▸ Advanced, on by default as in Arc. |
| Restore windows from previous session | Settings ▸ Advanced | done | Settings ▸ Advanced; off keeps the window in use last. |
| Block Cookie Banners | Settings ▸ General | done | Settings ▸ Privacy; hides the common consent managers' banners (CookieBanners), off by default as in Arc. |
| Archive Little Arcs after | Settings ▸ Links (6 hours default) | done | Settings ▸ Links; a Little Window left alone that long closes into the archive. |
| Previews (Gmail, Calendar on Favorites; live PR cards) | Settings ▸ General ▸ Previews Settings…, a Calendar favorite's menu ▸ Live Calendar | done | Gmail: the unread mail from Gmail's Atom feed (the space's own sign-in) in Arc's card, rows, ＋ and motion, measured on Victor's signed-in Arc 8 Nov. Calendar: Arc's timeline card, gear menu, Live Calendar ▸ submenu, tile countdown and meeting link; events read through Google's Calendar embed (Arc's own fetch says "Failed to update" in 1.172.1). See "Previews, measured". GitHub live PR rows show a snapshot hover card, with checks fetched on hover; GitHub Pull Requests is appended to the Previews checkboxes. |
| GitHub live folders: pull request card | Hover a live PR row; Previews ▸ GitHub Pull Requests | done | Snapshot title, draft, labels, tasks, comments and updated time; checks fetched once per revision on hover through the space session. Arc binary has Checks/FailingCheck and pullRequestShowAllFailures (24 Nov 2026). No row glyph or review state. |
| Join Meeting ⌃⌘J | Shortcuts | done | The call on now, else the next one today, from a Live Calendar favorite. |
| Music notes on a playing favorite | A favorite on a music site, while it plays | done | Core Animation notes rise from the playing icon's top edge and stop when the sound pauses. As in Arc 1.172.2 (live, 11–12 Nov 2026) they keep floating on a muted tab and with Reduce Motion on. Compared side by side with Arc in full windows at 1x and 2x, light and dark spaces, top row and lower rows; light notes use 30% black, dark notes 80% white. |
| Troubleshooting menu | Help ▸ Troubleshooting: Record Trace, Open Task Manager, Reveal Arc Data, Copy Arc Info | done | Export Diagnostics…, Open Task Manager (Chrome's), Reveal Cra Data, Copy Cra Info; Record Trace is Arc-internal. Open Task Manager has no shortcut in Arc 1.174.3 (its MainMenu.nib; Chrome binds ⇧⎋ only off the Mac); in Cra it opens with no tab in front too, from any open page (#855), and Settings ▸ Shortcuts can give it one. |
| Page zoom | View ▸ Zoom In / Zoom Out / Zoom to Actual Size (⌘+ ⌘− ⌘0): Chrome's steps (100 → 110 → 125 %), each one shown as a toast at the page's top right ("125%", "100%"), gone after about 4.9 s or a click | done | Measured in Arc 1.174.3 (26 Nov 2026): the same ShinyToast as every other toast; no lasting badge in the address bar or sidebar field. `PageZoomSteps` (CraCore), `page-zoom-toast` scenario (#856). |
| Help menu | Getting Started, Release Notes, Contact the Team, Visit Help Center, Restore Data | done | Cra Help (Arc's Help Center and Getting Started guide), Release Notes, Report an Issue… (Contact the Team), Essential Keyboard Shortcuts, Troubleshooting ▸ Task Manager / Reveal Data / Copy Info. *skip*: Restore Data and Export Arc Notes (Arc's account and Notes), Record Trace (chrome://tracing is a developer tool). |
| Ad blocker upsell card, Account, Sign Out, Send to Dia, Share Space | | *skip* | Account/cloud. |
| Membership card, Gift Arc to a Friend | Settings ▸ Account | done (Cra's own) | Settings' first tab, named after the user like Arc's (GitHub #372): a member card made on the Mac (macOS name, a nickname, EARLY '26, a months stamp in the first year, then anniversaries, the day Cra first ran), its share, save and copy buttons, the default-browser banner, and "Share Cra with a Friend", whose sheet copies or shares crabrowser.app tagged `utm_campaign=share`. No account, server or gift unlocks. |
| Space icon: Emoji and Icon tabs | Space header icon, Edit Space… | done, plus an Image tab (Cra's own) | Arc's picker has Emoji and Icon. Cra adds Image (GitHub PR #395, Victor agreed 12 Nov 2026): a PNG, SVG or other picture, chosen or dropped, stored as a 96 px PNG in `Space.iconImage`. The dock fades it like an emoji while its space is closed. An older Cra shows the space with no icon (a dot) and drops the picture when it saves. |
| Max: 5-Second Previews | Settings ▸ Max | done | Arc's hover cards on the Mac's Apple Intelligence: Arc's links on Google, X and Hacker News, or Shift on any link (the small card within the site); Arc's prompt, card, timing and share menu (arc-reverse-engineering.md). |
| Max: Ask on Page | ⌘F, Settings ▸ Max | done | Arc's find-or-ask card on the Mac's Apple Intelligence (#393): typing finds, Ask asks about the page with Arc's prompt, quotes with Find on Page, "This page was long, so I read the first N%." (arc-reverse-engineering.md). |
| Max: Instant Links | ⌘T, Settings ▸ Max | done | Shift-Return on a search in ⌘T, on the Mac's Apple Intelligence (#407): the "Searching the web for you…" row with Arc's spinning flower, then the top Google results as tabs, a split or a folder, placed as Arc places them. Only the queries leave the Mac, to the search engine. Differences: counts the phrase states are honoured (Arc ignores them), only the top result opens otherwise (Arc often opens every result on the page), a split holds at most 4 panes, a model that fails falls back to searching the phrase as typed, and there is no Brave fallback: when Google's page can't be read Cra opens Google's results page for that search (one tab, whatever the count), and an incognito space or another engine opens that engine's results page, one per search (arc-reverse-engineering.md). |
| Max: ChatGPT in the Command Bar, New ChatGPT Message ⌥⌘G | ⌘T, ⌥⌘G, Settings ▸ Max | done | Victor asked for it as in Arc (#828, 27 Nov 2026). Off by default; "chatg" + Tab scopes ⌘T to ChatGPT ("Ask ChatGPT  Tab", pill in Arc's #75A99C, "Send a Message…"), a question gets the "Ask ChatGPT" row third, ⌥⌘G opens the bar scoped (the plain bar when off). The message opens chatgpt.com/?q= as a new tab, as a site search does; Cra itself sends nothing to OpenAI. Measured live on Arc 1.174 (arc-reverse-engineering.md). Arc 1.174's own Return in that scope opened nothing in two tries (presumably a remote gate), so where it opens follows Arc's other site searches. |

## 2. Menu bar and shortcuts

Arc's actions (Settings ▸ Shortcuts, 106 rows) that Cra has no action for:

| Arc action | Arc shortcut | Cra |
|---|---|---|
| Collapse Pinned Tabs (View) | — | done |
| Reveal Tab in Sidebar (Tabs) / Reveal Current Tab | ⌃Space | done |
| Reset all tabs in this Space (Tabs) | — | done |
| View Archive… / Clear Archive (Archive menu) | — | done |
| View History (Archive menu) | ⌘Y | done | Chromium's History page in a new tab of the space in use, so its profile's history (GitHub #590, `HistoryPage`). Arc 1.172's MainMenu.nib: action `viewHistory`, selector `showAllHistory:`. Until #590 Cra's ⌘Y opened the archive, which is View Archive… |
| Collapse All Folders / Expand All Folders | — | done |
| Next Tab / Previous Tab, second binding | ⌘} / ⌘{ | done |
| Go Back / Go Forward, second binding | ⌘← / ⌘→ | done | Bound since the first build; as in Chrome they act only when the page leaves the key alone (a text field keeps ⌘← for the line start). |
| Developer Tools, second binding | F12 | done |
| Go to last Sidebar Item | ⌘9 | done |
| Switch to Split View 1–4 | ⌃⇧1…4 | done |
| Expand Current Split | — | done | View ▸ Expand Current Split and the command bar ("expand", "maximize"), no default shortcut, as in Arc 1.172.2 (measured live 11 Nov 2026, docs/arc-reverse-engineering.md "Expand Current Split"). The focused pane takes the window and the others keep the 220 pt minimum, stored as width factors 1 and 0; laid out in one frame. Cra's pane minimum went from 200 to Arc's 220 pt with it. |
| Drag a tab onto the page to split | drag a sidebar tab over the page | done | Arc 1.173.1, measured with real drags (13 Nov 2026, docs/arc-reverse-engineering.md "Drag and drop"): on a lone page the nearest edge opens an empty pane there, left or right side by side, top or bottom stacked; in a split a pane's sides (a fifth each) and the gaps open one between panes, and a pane's middle rings it to be replaced (it goes back to the sidebar). Nothing next to the sidebar (40 pt), no fifth pane. The page shows the tab from before the press while the drag offers a split, and the drag image is Arc's dark card. *Cra's own (Victor, 13 Nov 2026, #419):* a page's link does the same near a pane's edge (60 pt), never replaces a pane, and leaves the rest of the page to the page; Arc takes no link there. Not measured: how far in a pane's edge reaches in a split (Arc: past 20 pt, short of a quarter), the region's colour on light themes. |
| Hold a dragged tab at the sidebar's edge to change space | drag a sidebar tab to the sidebar's left or right edge and hold it there | done | Arc's `TablistEdgeDragController` (fields `timer`, `proposedDirection: Direction` = `next`/`previous`, `lastDragPosition`, `switchThreshold`, read from its Swift metadata 17 Nov 2026) pages the sidebar while a tab is held at its edge (#499, a user's muscle memory from Arc). Cra (`SidebarEdgeDrag`): the right edge, from 6 pt inside the sidebar to 30 pt over the page or past the window, pages to the next space and the left edge to the previous one, every 0.5 s the tab stays, stopping at the first and last space; the drag goes on in the new space's list. Not measured: Arc's `switchThreshold` (0.5 s is Cra's space-icon wait), the band's width, whether Arc wraps past the last space, any highlight at the edge. |
| Open Extensions | ⌘E (hold ⌘, tap E to step through, let go to open: #709) | done |
| Show Little Arc "Open In" Menu | ⇧⌘O | done |
| Open Little Arc or Peek in… | ⌘O | done | 11 Nov, Arc 1.172.2: Tabs ▸ "Open in <space>" after Pin Tab, with the space's icon, shown only while a Little Window or Peek is in front, out of the Window menu; ⌘O moves the page there at once (the picker is ⇧⌘O). Settings ▸ Shortcuts lists it under Tabs as "Open Little Window or Peek in…". |
| Network Inspector | — | *skip* (DevTools has it) |
| Exit | ⎋ | n/a |

Naming differences (Cra → Arc): "Close Tab" → "Archive Tab" for ⌘W in Shortcuts; "Go to Space N" →
the space's name ("Victor ⌃1"); "Hide Sidebar" → "Show/Hide Sidebar" in Shortcuts; Spaces menu
"Edit Space…" → "Edit Theme…" and "Rename Space"; Tabs menu "New Folder" → "New Folder…"; File
gains "New Profile".

## 3. Right-click menus

| Where | Arc items Cra lacks |
|---|---|
| Today tab | all done, in Arc 1.173.1's order (GitHub #600): Customize Page… opens the site's Boost editor; Archive Other Tabs and Archive Tabs Above are the ⌥ rows. Cra keeps Use Page Title and Use Site Icon (no other way in) |
| Pinned tab | all done, in Arc 1.173.1's order (GitHub #600): except Edit Pinned Page ▸: Cra lists its Edit Pinned URL… and Replace Pinned URL with Current flat, right after Rename… (#76, asked again on #600). Remove Pin archives the tab as Arc's does |
| Favorite | all done, in Arc 1.173.1's order (GitHub #600) except Share ▸ (http pages only) and Move to ▸ Profile (shared favorites only). Remove Favorite archives a space's own favorite (Arc deletes it; Library brings Cra's back); ⌘Z right after puts either kind back in its place, as Arc's undo does (#806). Cra keeps Tile Color ▸ and Use Site Icon |
| Split | all done, in Arc 1.173.1's order (GitHub #600): Share Split View… (Arc's warning sheet, a crabrowser.app link like Share Folder…), Change Icon… (Arc's Emoji / Icon picker; the row then shows the icon and "N Tabs"), the pane submenus' Share ▸, and Archive Other Tabs / Archive Tabs Below / Above in Today. Archive Tabs Above and Other Tabs are the ⌥ rows. The toast after Share Split View… is Share Folder's ("Copied Folder URL"); Arc's couldn't be seen offline |
| Space header / empty sidebar | Share Space… (*skip*), New Folder, Manage Spaces…, Delete Space (check order) |
| Folder | Paste as New Tab, Duplicate, Turn "…" into Space, Copy All Links, and Arc's order (New Nested Folder… is Cra's New Folder Inside). Move to ▸ done (GitHub #662): every space, ✓ on its own, New Space…; the folder and everything in it goes to the end of that space’s Pinned. Arc 1.174's folder menu, read over AX on an offline copy (21 Nov 2026): Share Folder… ─ New Nested Folder…, Turn “…” into Space, Copy All Links, Copy All Links as Markdown ─ Change Icon…, Rename… ─ Duplicate, Move to ─ Delete; Cra's Move to ▸ sits where Arc's does, last before Delete. Share Folder… done (GitHub #357): Arc stored the folder on arc.net; Cra's crabrowser.app/folder link carries it after the # (FolderShareLink), so nothing is stored and the server never sees it. Same toast, "Copied Folder URL", after Arc's "Send this Folder to anyone" warning (AppDialog.shareLink, #356) |
| Toolbar address | Share ▸ (in the Site Control Center), Disable Shared Quotes (arc.net); the rest done. Blocked pop-ups (GitHub #357): Arc keeps Chromium's list (hasBlockedPopUp, showBlockedPopups) but its button wasn't seen yet; Cra shows Chrome's crossed-out window before the sliders, or "Pop-ups Blocked" under the sidebar's address, with Chrome's list and Always Allow as a menu |
| Library button | Show media ▸ Documents, Desktop, Screenshots, Arc Captures, Downloads (Cra has them on the Library rail's Media button; Screenshots there also decides whether new screenshots join the downloads list) |
| Back / Forward | done (GitHub #416): Arc's BackForwardList menu, its ArcMenu hung under the button, tail up on the button's centre, 10 pt below it; one 40 pt row per page that way (favicon 16 pt in, a 14 pt grey square for a page without one, title 40 pt in, 13 pt medium cut to 160 pt), the nearest first, at most 12 (Chromium's cap, not seen in Arc). Checked against Victor's Arc 1.172.2 live (13 Nov 2026): a right-click on the toolbar's ← and on the sidebar header's → opens it, so does a press held about 0.8 s (Arc 794–848 ms to the window, Cra 782–790 ms) and the release then doesn't navigate; a ⌃-click is a plain Back/Forward. Arc's window is 6 pt larger all round for a soft drawn shadow with no rim (232 × 74 pt for one row). History from DevTools Page.getNavigationHistory; WebKit pages answer it from their backForwardList |

## 4. Settings

The window is Arc's since GitHub #372 (684 × 650 pt, eight tabs in a toolbar, measured on Arc 1.172.2: see "Arc Settings window" in
arc-reverse-engineering.md). Arc's seven tabs after Account are Cra's in Arc's order; Cra's first tab has the member card, sync and Share Cra in Account's place (no account) and carries the user's first name, and
Privacy and Extensions follow Advanced. Tabs, Plugins and Performance have no tab: their rows sit in General, Extensions and Advanced.

| Arc tab | Rows Cra lacks |
|---|---|
| General | Previews Settings… lists all seven of Arc's previews in its order (#376). Outlook Mail and Calendar read with the page's own sign-in (a hidden Outlook page's own service requests), not Arc's Microsoft Graph sign-in; Notion Calendar shows the profile's Google calendar, as Arc's does. Live Calendar in the Calendar favorite's menu, as in Arc; Block Cookie Banners done, under Privacy |
| Profiles | "New documents" app (GitHub #375); Search engine, Archive tabs after and Download location are on each profile's card (the engine and the archive time are one setting for all profiles); Privacy, Passwords, Credit Cards, Notifications and Clear Browsing Data done. Every profile can be renamed, Default too (GitHub #666), and Chromium calls it the same: Arc keeps its names in Local State's profile list (`profile.info_cache`), Cra writes each loaded profile's `profile.name` pref, which Chromium copies there (ChromiumProfileNames) |
| Max | "Automatically enable future Arc Max features" has nothing to enable yet |
| Shortcuts | (The choice per shortcut of Cra or the website done, GitHub #374: Arc's pop-up and lines with Cra for Arc, saved as `priority` on the action's chords in keybindings.json. Each action starts where Cra had it: the formerly reserved ones Prefer Cra, the rest Prefer Websites, not Arc's own per-action defaults. The menu's order, Prefer Cra / Use Both / Prefer Websites, is Arc's `priority` declaration order from the binary, not seen in Arc's open menu. Use Both: a press the page doesn't hand back within 0.5 s counts as kept, Cra shows "Press ⌘W again to Close Tab" with Arc's "Edit the shortcut" and takes the next press while the toast shows; Arc's toast text is built in code, so that sentence is inferred from its comment "<do something> again to <do action>". A page never keeps Quit, Hide, Hide Others or Minimize (Arc measured for ⌘Q and ⌘M), and keeps ⌃⌘F only to enter full screen, as in Arc (GitHub #480, PR #485)) |
| Links | ("Open Little Arc when clicking on links with ⌥⌘ held" done, GitHub #373, as "⌥⌘-click opens a Little Window". *Deviation, pending Victor:* off by default where Arc's is on, because since 0.1.38 a ⌘⌥-click opens Split View (#298, Chromium 156's split view click) and the switch takes that click over. The click itself isn't measured in Arc; see `LittleWindowTrigger`); Archive Little Windows after done. Cra's own, not in Arc: "⌘-click Expand opens in the tab" (GitHub #380, off by default as Victor asked, 12 Nov 2026), a ⌘-click on a Peek's Expand loads the page in the tab the Peek came from (`PeekExpand`); Split View's "Middle-click a link in a split to add a pane" and "More than four panes in a split" (GitHub #498, both off by default as Victor asked, 18 Nov 2026; `LinkSplitClick.middleClickAddsPane`, `SplitPaneLimit`) |
| Advanced | Shared Quotes (arc.net); "Show full URL when Toolbar is enabled", "More Settings…" and "Reset Translated-site Prompts" done (GitHub #373); Export Data (Arc's Markdown of every space and tab) isn't in Cra |
| Icon | Cra has its own icon picker. The pick shows in the Dock (and the Dock tile plug-in after Cra quits). Unlike Arc's AppIconApplier it never goes on the app itself, so Finder, /Applications and Launchpad keep Cra's own: Finder's custom icon on the bundle breaks the app's signature (GitHub #724; 0.1.54 and 0.1.55 did it as Arc does; AppIconBundle, scenario app-icon-signature) |

## 5. Animations and styling

- Command bar (⌘T / File ▸ New Tab…), 7 Nov 2026, 57 fps region recordings of both apps: Arc's bar is
  there complete from one frame to the next, no fade or scale; Cra's too. Matches.

- Command bar tone in dark mode (#502, Jelena Jansson's research, 18 Nov 2026): Arc's bar is see-through,
  (26,26,26) over a black page, ≈ 30 over a mid-dark photo, 45–48 over a white page. Cra's stayed at 45–50
  over anything ((46,45,45) at 0.97 over `.hudWindow`). Since 20 Nov the tint is a neutral 26 grey at 0.85
  (CraCore `CommandBarTones.panel`): 26 over black, 36 over 128 grey, 47 over white, measured on macOS 26.
  Arc's mid-tones come out a few levels darker than Cra's; the ends match.

- Boost editor, 7 Nov 2026, 60 fps recordings of both apps (BoostEditorMotion): Arc draws the panel at
  85 % on its first frame and grows it to full size in 0.28 s about the middle of its right edge, no fade;
  it closes from one frame to the next. Code widens it 183 → 480 pt in 0.35 s with the 480 pt layout
  centred and clipped on both sides meanwhile; Back narrows it in 0.13 s. Ease-out throughout. Cra
  matches after this sweep (it had no opening animation and resized with AppKit's default). Arc's code
  header is only Back and a centred CSS / JS switch; Cra had the boost's name and Undo there too.

- Sidebar ⌘S, 8 Nov 2026, `screencapture -V` at 60 fps, four Arc runs and two of Cra each way (SidebarMotion): Arc's
  page edge covers about 43 / 72 / 89 / 97 % of its travel after frames 1–4 hiding and 30 / 69 / 89 / 97 % showing,
  done in 5 frames. Cra ran ahead (67 / 87 / 96 / 99 %, fitted to an ffmpeg recording that had dropped Arc's first
  frames); now 0.085 s on (0.3, 0.7, 0.5, 1), measured 23–48 / 60 / 83–85 / 96–98 % hiding and 30–47 / 65–76 /
  86–92 / 96–98 % showing. ffmpeg's avfoundation capture misses window moves; `screencapture -V` doesn't.

- Previews cards, 8 Nov 2026: see "Previews, measured".

- Music notes over a playing favorite, 10 Nov 2026 (MusicNotes, MusicNotesView): particle values, the
  music-site list and placement reference Arc 1.172.1; methods and uncertainties are in
  [the research notes](arc-reverse-engineering.md#music-notes-on-a-playing-favorite-arc-11721-build-90370-10-nov-2026).
  Paired dark-theme footage and light-theme screenshots of YouTube Music were compared with Arc;
  live pause/resume was checked in CraDev. The independently drawn light notes use 0.3 black opacity,
  visually fitted to those captures; dark notes use 0.8 white. Tests cover host eligibility, immediate
  sound state, mute/pause/resume, placement and sprite tint at 1x/2x.
  11–12 Nov 2026: Arc 1.172.2 (the user's own, on www.nts.live) and a Cra test copy in 1280 × 800 windows
  on a virtual display at 1x and 2x, light and dark spaces, the playing favorite in row 2. Origin, rise,
  growth, fading and the drift over the tile above match; pause stops both within 0.2 s. Two differences
  were fixed: Arc keeps the notes on a muted tab and with Reduce Motion on, where Cra hid them (the muted
  case changes #303's locked promise, Victor's decision). Density and fan width differ within sampling
  noise. A real music site on a release build, splits, drags and swipes stay on
  [release-checklist.md](release-checklist.md#sidebar-tabs-and-the-command-bar).

Not re-measured in this sweep: earlier sessions measured the command bar, split view,
Peek, Little Arc, PiP, folders, space dock, Library swipe, dialogs, toasts and toolbar against Arc
(docs/arc-reverse-engineering.md). New surfaces built from this list are matched to captures taken
in this sweep (Essential Shortcuts window, Library pages).

## Built in this sweep

- Window ▸ Stay On Top; File ▸ Capture Full Page and Save Page As (⇧⌘S, single file or HTML only);
  Edit ▸ Copy URL as Quote (⌃⇧⌘C, a text-fragment link instead of Arc's arc.net card).
- Copy URL, Copy URL as Markdown and the sidebar's Copy Link leave out utm_* and click ids
  (CleanURL).
- View ▸ Collapse/Expand Pinned Tabs; View ▸ Appearance (Automatic / Light / Dark for websites and the browser).
- Tabs ▸ Reveal Tab in Sidebar (⌃Space) and Reset all tabs in this Space; Archive ▸ View Archive… and
  Clear Archive; Collapse All Folders / Expand All Folders; Open Extensions (⌘E); Switch to Split
  View 1–4 (⌃⇧1…4); Next/Previous Tab on ⌘} / ⌘{ too; Developer Tools on F12 too; ⌘9 = last tab.
- Today tab menu: Archive Tabs Below.
- Help ▸ Essential Keyboard Shortcuts (Arc's card, checked side by side at 2x); Help ▸
  Troubleshooting with Export Diagnostics…, Reveal Cra Data, Copy Cra Info.
- Settings ▸ Advanced ▸ Play Cra sound effects.
- Library ▸ Media and Window ▸ View Media…; File ▸ Capture in Portrait Mode; the toolbar address
  menu's Capture…, Capture Full Page, Manage Extensions… and Hide Toolbar.
- Settings ▸ Tabs ▸ Archive Little Windows after (1 hour, 6 hours, 12 hours); Settings ▸ Profiles ▸
  Your Data and Settings (Chromium's privacy, passwords, cards and notifications pages per profile).
- Sidebar tab menu: Add Split View on the open tab, Open in Split View on any other.
- View ▸ Cast… and Help ▸ Troubleshooting ▸ Open Task Manager, Chrome's own (ExecuteChromeCommand).
- Sidebar tab menu: Change Icon… and Share ▸.
- Settings ▸ Advanced ▸ "When opening Cra, restore windows from previous session".
- Show Little Window "Open In" Menu (⇧⌘O): the Little Window's list of spaces.
- Settings ▸ Advanced ▸ "Allow websites to get your theme data": Arc's `--arc-palette-*` variables,
  measured live in Arc (names, #RRGGBBAA format, no trace in the page's markup) and fitted to the
  semantic palette Arc stores per space.
- Edit ▸ Find ▸ Use Selection to Find and Jump to Selection (⌘J).
- View ▸ Expand Current Split (11 Nov 2026): the focused split pane takes the window, the others keep
  Arc's 220 pt minimum (SplitPaneLayout.expanding).
- Previews for a Gmail favorite: unread mail in Arc's card on hover (Settings ▸ Tabs); 8 Nov: Arc's full card
  (sender, age, subject, two lines, scrolling past 270 pt, ＋ for a new mail, rows open the mail) and its motion.
- Live Calendar on a Google Calendar favorite (8 Nov, Victor's choice: a working version, as Arc's no longer reads):
  today's timeline on hover, the gear's Last fetch / Refresh / Disable Live Calendar, the favorite's Live Calendar ▸
  submenu (Show Hover Preview, Show Time to Next Meeting, Show Next Meeting Link ▸ Never … Ten Minutes Before), the
  tile's countdown, a Join card from two minutes before a call, and Join Meeting ⌃⌘J.
- Boosts: New Boost, the editor, Zap, CSS/JS code, Library ▸ Boosts, Window ▸ View Boosts…, the Advanced switch.
- Window dragging from the top of webpages (Victor's choice, 7 Nov: on, as in Arc).
- AppleScript, Arc's dictionary (Victor's choice, 7 Nov: like Arc, JavaScript off by default).
- Settings ▸ Privacy ▸ Block cookie banners (Arc's "Block Cookie Banners", off by default).
- Easels, first version: File ▸ New Easel (⌃⇧E) opens a canvas in the tab (EaselBrowser, a page
  engine of its own like WebKitBrowser, so sidebar.json is unchanged: the tab's address is
  easel://<id>, the drawing Easels/<id>.json); Library ▸ Easels and Window ▸ View Easels….

## Easels, measured (Arc 1.172.1, offline copy, 7 Nov 2026)

- File ▸ New Easel (⌃⇧E) adds an "Untitled Easel" row to Today (AX `EaselCellView`, an easel glyph) and
  opens it in the page area; the toolbar's address shows its name.
- The page area is a native canvas (`easelCanvasView`), as wide as the page and 2436 pt tall, scrolling.
  A title text box 894 pt wide sits centred 52 pt below the top, selected on creation (blue outline with
  round corner handles), "Untitled Easel" in bold white about 22 pt; beside it a black pill with +, Aa
  and − (text size).
- Bottom left, 16 pt in: a toolbar of 36 pt buttons 38 pt apart on #100D00 (the palette's dark
  backgroundExtra): Pointer, Image, Text, Ellipse, Rectangle, Arrow, Freehand, then captures. The picked
  tool sits on #716328 with 8 pt corners; glyphs in #FAEEC2 (foregroundPrimary). Bottom right: a 36 pt
  share button (person.badge.plus), cloud sharing in Arc.
- Edit ▸ Find in an Easel (Arc 1.172.2, Victor's Arc, 11 Nov 2026, over AX): with the caret in a text box (an
  `AXTextArea`, Arc's rich-text editor), every Find item is off, Find and Replace included. Pressing it from the menu,
  ⌥⌘F or ⌘F opens no find bar and leaves the text as it was. On a web page, Find… is on and Find and Replace is off.

## Easels, item by item (Arc 1.172.2, Victor's Arc, 11 Nov 2026)

How it was read: Arc's own model from its binary (Swift field metadata of `EaselObject`, `EaselShape`, `WebCard`,
`LinkData`, `EaselDocument`; the strings of `EaselObjectMenuProvider` and `EaselCanvasMenuProvider`), the
`ARC_EaselUI.bundle` export viewer (EaselExportViewer.js/.css draw every kind of object), the colour sets in
`ARCClients_BaseAssets.bundle`, and a throwaway easel in Victor's Arc read over AX with 2x window captures
(menus by right-click, the colour picker and link card measured from pixels). Cra's side: CraCore
`EaselObjects`, `EaselHistory`, `EaselSnap`, `EaselLinkMetadata`; the app's `EaselCanvasView`, `EaselCards`,
`EaselLivePage`, `EaselServices`.

| Arc | Cra |
|---|---|
| Shapes are filled at 75 % and stroked 2.5 pt in one colour; new ones are light green (rectangle), red (ellipse), light blue (arrow), black/white (stroke); arrows have two flares at 45°, min(32, 0.3 × length) | done (`Easel.defaultShade`, the canvas's `draw`) |
| Eleven colours in two palettes, Vibrant (Arc's default) and Chill; black and white swap in the dark | done (`Easel.hex`; files keep the colour's name, so a palette change recolours) |
| Canvas menu: Paste, —, Color Palette ▸ Vibrant / Chill, —, Use Alignment Guides | done |
| Alignment guides: a moving item's edges and centre snap to the others' and a line shows | done (`Easel.snapped`, 6 pt; ⌘ while dragging turns them off for that drag) |
| A picked shape shows a colour picker above it: a black 180 × 69 pt panel, 20 pt dots 26 pt apart in two rows (black, yellow, pink, red, light green, dark green / white, gray, purple, light blue, dark blue), a check on the current one | done (`EaselColorPicker`) |
| A click with the rectangle or ellipse tool places a 200 × 200 pt shape centred on it; a drag draws one | done (`Easel.shape`) |
| Object menu: Bring to Front, Send to Back, Delete, —, Cut, Copy, Paste, —, Duplicate (same for shapes and link cards) | done; the strings' other rows follow for their kinds: Add/Edit Alt Text… (pictures), Set as Easel Thumbnail / Reset to Default Thumbnail (pictures, captures; the Easels page then shows that picture), and for a capture Show Live Website / Show Screenshot and Copy Capture URL |
| One item picked at a time (the canvas holds a single `selectedObjectFrame`) | Cra's own, not in Arc (GitHub #580, Victor 20 Nov 2026): picking works as on the rest of the Mac. ⌘- or ⇧-click adds or removes an item, a drag from empty canvas draws a selection box that picks what it touches (⌘/⇧ flips them in the picks), ⌘A picks all. The group moves and snaps as one box, and the object menu, Cut/Copy/Paste, Duplicate, Delete and the colour picker (when every pick is a shape) act on all of it. Corner handles, the text pill and live-card clicks stay with a single pick (`EaselSelection`) |
| A fixed-width canvas that grows down with its items, and zooms (`CenteringScrollView`, `ZoomInteraction`; its web export sizes the page from the lowest item) | Cra's own, not in Arc (GitHub #580, Victor 20 Nov 2026): the canvas is endless in every direction. It always reaches a whole view past the home sheet (the window's width × 2436 pt, where older easels sit), the items and what is in view, so scrolling or dragging toward any edge finds more room, left and up too; it fits back round what is there when a scroll or edit ends. A pinch or View ▸ Zoom In/Out/Actual Size (⌘+ ⌘− ⌘0) zooms it from 0.1× to 4×. A drag past the view's edge scrolls on (`EaselCanvas`) |
| Undo and Redo (EaselEditManager's undo labels) | done (`EaselHistory`: a move, a resize, a typing session, a colour… is one step each; Edit ▸ Undo ⌘Z, Redo ⇧⌘Z) |
| Cut, Copy and Paste of objects (Arc's `company.thebrowser.Browser.easelObject` pasteboard type) | done (`dk.kildahl.cra.easel-items`, with a picture, address or text for other apps; pictures come along to another easel) |
| A pasted web address becomes a link card: the page's og:image across the top, then a 59 pt black bar with the site's icon (26 pt), the title (#D8D8D8) and a 36 pt ↗; 459 × 324 pt; no resize handles; the selection follows its rounded edge; a tooltip with the whole title and address | done (`EaselLinkMetadata` reads og:title/og:description/og:image and the icon as Arc's MetaTagParser does, once, without cookies); ↗ or a double click opens the page in a tab |
| A dropped address or sidebar tab | done (a link card; Arc's pasteboard reader takes addresses; a sidebar tab dropped on Arc's canvas wasn't tried live) |
| A YouTube link becomes an embedded player (in 1.172.2 it shows YouTube's "Video player configuration error, Error 153") | Cra on purpose: the link card with the video's picture and a ▶; ↗ or a double click plays it in a tab |
| A capture sent to an easel is a web card that keeps its page, title, icon and where on the page it was (CaptureLayoutInfo), and can be flipped to the live site ("Replace this screenshot with the live website?", asked once) and back | done: the capture menu's New Easel and Send To… keep the page's address, viewport, scroll and the captured area; Show Live Website runs the page windowless at its captured size and draws the captured part on the card every second (only when it changed); a click on a picked live card reaches the page there, a link in it opens in a tab |
| The web card's look | from Arc's export viewer (10 pt corners, a hover bar with the icon, the title and ↗), not measured live: a scripted capture in Arc never reaches its menu (also seen 4 Nov) |
| Sharing (Arc's share warning, "Copied Easel URL"; viewable in any browser, editable only in the app) | done without a server: Share Easel… on an easel's sidebar row and its Library card copies a `crabrowser.app/easel#…` link that carries the easel itself, pictures shrunk to fit (`EaselShareLink`; past 400,000 characters they are left out and the toast says so). The site draws it read-only in Cra's dark look; its Open in Cra (`cra-easel:`) adds a copy after asking (`EaselShare`). A capture travels as its picture and page, not where on the page it was, so it can't go live. Collaborators' avatars and presence: *skip* (cloud) |
| Embedded browsers (`WebBrowser`) and rich text objects | *skip*: in Arc's model, but no tool, menu or paste in 1.172.2 makes one |
| Save as web page / Export All Easels | *skip*: Arc's wind-down; Cra's easels are already files in its data folder |
| Arc's text fill style (`EaselFillStyle.contentHugging`, its PaintBucketIcon) | not in 1.172.2's text pill (+, Aa, − only), so not built |

The easel file: items Cra 0.1.40 can read stay in `items`; link cards and captures go in `cards`, which it skips (it
fails on a kind it doesn't know, and would show the easel empty); each item carries `z`, its place in the stack
(fixtures `easel-0140.json` and `easel.json` in CraCore's Fixtures/Model).

## Capture menu, measured (Arc 1.173.1, 17 Nov 2026)

Read from a 2x still of the menu beside a capture, with two easels ("Test", "Movies") in the library
(CraCore `CaptureMenuLayout`; the app's `CaptureMenu`).

- 273 pt wide and, with nine rows, 433 pt tall: a field 12 pt down, 30 pt tall and 10 pt in from both
  sides, with the prompt "Send To…" and the caret in it as the menu shows; the first row 7.5 pt under it;
  40 pt rows; sections 9 pt apart; 5.5 pt under the last row.
- Rows: Save to Library, Copy, Save..., Send via iMessage... | Edit, Retake | New Easel (a plus), then
  each easel by name with the easel squiggle. An easel is picked in the menu itself: there is no
  "Send To…" row opening a second list, which is what Cra had.
- Cra: the same field and rows without Save to Library and Edit (no counterpart yet). Typing narrows
  every row by its title, Return runs the picked row or the first one left, ↑ ↓ move, Escape ends the
  mode. At most eight easels are listed, the latest edited first; typing reaches the others. What the
  field does in Arc wasn't tried (Arc can only be looked at here), so the narrowing is Cra's reading
  of it.
- A capture sent to an easel that is open in a tab goes onto its canvas, which shows and saves it.
  Before, it was written to the easel's file and the tab then saved its older copy over it, so the
  capture never showed. Library ▸ Easels now follows an easel made, renamed or deleted while it shows.

## Easel toolbar, measured (Arc 1.173.1, 17 Nov 2026)

Read from 2x captures of a purple space's easel with the pointer over each button in turn, and from
key presses on the canvas (CraCore `EaselToolbarLayout`, `Easel.Tool.key`; the app's `EaselToolbar`).

- The bar is 44 pt tall, its 36 pt buttons 38 pt apart and 4 pt in. After Freehand comes a 5 pt gap
  with a 1 pt line in its middle (#20212A on the bar's #080913), then Duplicate, 4 pt from the end:
  313 pt in all.
- The picked tool sits on #4E4F7F. A button under the pointer gets a darker fill, #393A58, Duplicate
  too; the picked tool's fill doesn't change under the pointer. Cra's bar keeps its own fixed colours,
  so the two fills are the same steps over it (white at 22 % and 14.5 %).
- A tool under the pointer, and the picked tool, show their key in the button's bottom right corner:
  a bold lowercase letter of about 10 pt, its right edge 5.5 pt in and its baseline 4.2 pt up. Image
  i, Text t, Ellipse o, Rectangle r, Arrow a, Freehand p. The Pointer's button and Duplicate show none.
- With the canvas holding the keyboard, R picked the rectangle, O the ellipse and V the pointer, and
  Escape went from Freehand back to the pointer. I, T, A and P are taken from the letters drawn; they
  weren't each pressed. Nothing happens until the canvas has been clicked.
- Not measured: whether ⇧ with a letter picks the tool (Cra takes either case), and Arc's own cursors
  per tool (its bundle has Pencil, Shape, Text and Arrow cursor pictures; Cra uses the system's).

## New Space past the last space (Arc 1.173.1, 18 Nov 2026)

From Arc's code (arm64, read with objdump: `ARCUI.EdgeFeedbackView` at 0x1009dc240, its driver at
0x100215f1c and the lift at 0x10021d960) and a 120 Hz, 2x screen recording of four pulls on a dark
space, read frame by frame (CraCore `NewSpaceSwipe`; the app's `NewSpacePlusView`).

- A swipe left on the last space overscrolls the tab list on its rubber band, and that overscroll
  drives the feedback at the sidebar's right edge. From the code: shown = overscroll / 15 pt and
  ring = overscroll / 22.5 pt, each held to 0…1. In the recording the ring read 0.64 to 0.70 with
  the list 14.5 pt out (0.64 by the code).
- The feedback rides a spring toward "shown" (response 0.4 s, damping 0.8), not the overscroll
  itself, so it swings a little past and settles. On every step of it: the disc's left edge is at
  width + 5 − 47 × shown (30 pt disc, half way down, resting 12 pt inside the strip's edge; 10.75 pt
  inside the sidebar's visible edge in the recording), its alpha is shown / 0.2, and the bulge's
  opacity is 2 × shown.
- The bulge is a radial gradient layer twice the strip's width and as tall, from the sidebar's ink
  at 22 % at its centre to nothing at its rim. It slides from 10 pt inside the strip's right edge
  until its centre is on that edge, and the strip clips it, so what shows is the left half of an
  ellipse: widest at the disc, gone at the sidebar's top and bottom. In the recording it is 81 to
  84 pt deep half way down and 33 levels strong at the edge, fading evenly to nothing 620 pt above
  and below; the strip's own width isn't in the code read, so Cra takes 82 pt.
- With the ring full the disc turns over within 0.2 s, growing to 1.14 and back (recording), and
  Arc plays a generic haptic tick (`performFeedbackPattern: 0`), as it does when the ring stops
  being full. Lifting the fingers starts a new space only if the ring has been full for more than
  0.1 s; otherwise the feedback springs back out and nothing happens.
- The ring is 2.5 pt (code) and runs from the top, counter-clockwise; the plus is 12 pt across
  (recording). Colours on the dark space: ring white 93 %, plus white 80 %, the disc's inside darker
  than the sidebar (black 22 % fits), turned over a plus of black 68 %, and 3 pt of shade under the
  disc. Arc's asset catalog names them `AddSpacePlusProgressColor`, `…IconTintColor`,
  `…BackgroundColor` and `…IconActivatedTintColor`: white or black in dark, and #2702C2 (Display P3)
  with white in light. The same disc is the Add Space card in
  Library ▸ Spaces (`SpaceManagementAddSpaceView`, 30 × 30 at 0x10039fcb0).
- It works with the sidebar docked and with it hidden and out over the page.
- Arc then opens its Create a Space page in the sidebar, and so does Cra ("Create a Space, measured").
- Past the last space the list gives on Arc's own rubber band, which upstream measured past the
  Library (docs/arc-reverse-engineering.md, "Swipe into the Library": 300 px of fingers for 20.5 pt,
  D(1 − 1/(0.15 x / D + 1)) with x half the fingers' travel). It is about a quarter as giving as the
  band Cra's space swipe has past its other end, so the ring fills slowly: about 330 pt of fingers
  in a 254 pt sidebar. Cra uses it past the last space (`NewSpaceSwipe.overscroll`).
- The disc's colours follow the app's appearance, not the space's: in macOS Dark Mode it is white
  on every space (the recording's dark space, and other spaces by the report of the Arc user this
  was built with). The catalog's light variant wasn't seen.
- Not known: the strip's width in Arc's layout, and whether that band's D is the page's width (the
  fit gave 215 pt; over this range it hardly matters).

## Create a Space, measured (Arc 1.173.1, 18 Nov 2026)

From a 2x still of the page, a 148 s screen recording read frame by frame (120 Hz), and Arc's code
(the page is SwiftUI, `SpaceCreation/SpaceCreationView.swift`; its constants include the 36 pt rows
and the 8 pt spacing). CraCore `SpaceCreationDraft`, `SpaceCreationLayout`, `SpaceCreationAnimation`;
the app's `SpaceCreationView`. Positions are from the sidebar card's top-left, in a 250 pt sidebar.

- New Space is a page in the sidebar, after the last space, not a dialog. From the "+" past the
  last space it pushes in over about 0.18 s; from the dock's "+" menu about 0.25 s, the window
  taking the new space's colours on the way. Cancel brings the old space back from the left in
  about 0.1 s. The sidebar's top row stays; the favorites and the tab list give way to the page.
  It never draws over the web page on the way. While it is up the page area is the new space's
  empty page in the draft's theme (Cra: the window shows no tab and no split until it closes).
- A swipe back takes the page out under the fingers, the space's column coming back beside it. On
  the lift it leaves past half way or on a flick (the rule for a page between spaces), else goes
  back in over 0.2 s. CraCore `SpaceCreationSwipe`.
- A picture of three tilted cards (64 × 41 pt, top 79 pt), "Create a Space" (about 16 pt bold, top
  140 pt) and a two-line subtitle (about 13 pt, 16.5 pt apart, top 170 pt).
- The name: a 223 × 35 pt field at 13.6, 231 (radius about 6 pt), white at 6 % on a dark sidebar and
  about 60 % on a light one. It has the keyboard as the page opens (a blue caret, no focus ring),
  the placeholder "Space name…", and a dashed 18 pt "+" at 21, 239.5 that opens the icon picker in
  a popover under it (264 × 265 pt, Emoji and Icon). A picked icon takes the "+"'s place.
- Profile: a 36 pt row 6 pt under the field, white at 8 % on dark (12 % under the pointer), with a
  pill for the profile's name (about 21.5 pt tall) and an (i) 12.5 pt across. Its tip is Arc's own
  bubble (navy 12/15/70 with text 157/159/212 on the dark navy theme, radius 10 pt), up as the
  pointer arrives and fading over 0.25 s; Arc's reads "You can use a Profile to give this Space
  its own logins, history, and browsing data." Cra shows it in its Arc tooltip (ArcTooltip) after
  0.05 s, with the words its sheet had under Profile, and the Search Engine row has an (i) with the
  sheet's words for that choice. The pill's menu is
  a native one and isn't in a window recording; an item of it opens Create a new Profile. Cra's
  menu has the rows of Arc's Change Profile menu: Default, the profiles, a line, New Profile….
- Choose a Theme: a 36 pt row 7 pt under Profile. It opens the theme editor beside the sidebar
  (347.5 × 496 pt, an arrow at the row), and every change shows at once on the sidebar, the page,
  the button and the dock. A click in the sidebar closes it and the theme stays.
- Create Space: 223 × 35.5 pt, ending 94 pt above the sidebar's bottom, a deep shade of the theme
  (#A3164B on a pink #B8718A sidebar, #1C25FF on Arc's dark navy). Dim until the name has a
  character, then on at once, and off again with an empty name. Cancel is a text button centred
  73 pt above the bottom.
- The dock under the page loses its Library and "+" buttons, its items stand 28 pt apart (33
  before) and one more follows the last space: a lit dot, and the picked icon once a theme has
  been chosen. The space that was open is dimmed.
- Create Space, about 2.5 s. From Arc's code (0x102602250 to 0x102603974, and the press at
  0x102604428) and its frames:
  - The press runs `withAnimation(.easeInOut(duration: 0.4))`. The button and Cancel fade where
    they stand (0.17 s). Each other part goes 80 pt down and out, 0.03 s after the one under it
    (`.delay`): Choose a Theme 0.03, Profile 0.06, the name 0.09, the subtitle 0.12, the title 0.15.
    A part has faded by half its slide (0.2 s; the name is 36 pt down when it is gone).
  - The picture and the card are two faces of one thing: `rotation3DEffect` of π about the level
    axis (x 1, y 0, z 0; anchor centre, anchorZ 0, perspective 1), a `scaleEffect` with its own x
    and y, and an offset of half the page's height, all on `spring(response: 0.8,
    dampingFraction: 1).delay(0.3)`. So its place and its angle keep step: edge-on 0.52 s in, half
    way down. Measured at 120 Hz the drop is 1 − (1 + ωt)e^(−ωt) with ω 7.85 to within 3 % all the
    way (534 pt in a 1250 pt window).
  - The picture's top edge goes away first, and the card with the icon (62.5 × 79 pt, radius 5 pt)
    comes round top edge nearest. The far edge is 0.57 of the near one at 75° and 0.82 at 17°: an
    eye about 150 pt away. The width never changes; the height does: the 40 pt picture would stand
    109 pt edge-on, and the card comes from 1.4 of its height down to its own (96 pt at 0.60 s,
    88 at 0.73, 84 at 0.80, 79 at 1.0).
  - The card shows through the picture before the turn (a white sheet over it, half there 0.4 s
    in) and the picture's side cards show behind the card until about 0.85 s.
  - A glow of the theme pulses behind the card at 1.3 to 1.5 s; the card fades at 1.8 to 2.0 s; the
    space shows at about 2.5 s. A form opened after that is empty.
  CraCore `SpaceCreationAnimation` (`drop`, `turn`, `height`); the view plays it as one transform
  a frame, 120 a second.
- The page lays itself out by the sidebar's width; its SwiftUI view compares the width with 227 and
  190 (0x102602d4c, 0x102602ce8). Over 227 pt the rows carry a glyph. At 227 pt and under they
  lose it and their label starts 16 pt in. At 190 pt and under the subtitle is one string that wraps
  as it falls (three lines in a 165 pt sidebar) instead of breaking after "life,", and the Profile
  row stacks: 60 pt tall, "Profile" and the (i) on a line centred 16 pt down, the pill under them,
  23 pt tall, 8 pt inside the row's sides, its chevron at the end. Measured in a 165 pt sidebar.
  Cra's Search Engine row stacks the same way, and also whenever its pill has no room beside it.
- Cra's own: a new space starts on one random brand colour (#155, #170) where Arc starts on a
  dark navy; the page has a Search Engine row under Choose a Theme, which Arc's has not (#306, so nothing the sheet offered is lost); the picture is Cra's drawing;
  and the (i) tips carry Cra's own words.
- Not seen: Escape, Return and Tab on the page (Cra: Escape cancels, Return creates); a click on
  another space in the dock (Cra leaves the page for it); and whether a cancelled page keeps its
  text (Cra's opens empty).

## Boosts, measured (Arc 1.172.1, Victor's Arc, 7 Nov 2026)

- The command bar's "New Boost" opens the editor for the open site: a 183 × 588 pt floating panel 10 pt in
  from the window's right edge and 215 pt down (AX `boostsEditor`). Header 40 pt: Done (grey ✕), "My Boost ⌄"
  (Rename this Boost…, Shuffle, Reset all Edits, Delete this Boost, All Boosts…), Undo. A 147 pt colour wheel in a
  brushed grey frame with two handles; Invert lightness, Advanced color controls (a popover: Contrast, Brightness,
  Original Saturation sliders) and Reset to original colors, 42 × 38 each; a white card of 20 "Aa" fonts (5 × 4,
  26 pt cells); Size and Case (69 × 38); Zap ⚡ and Code {} (147 × 38). Code widens the panel to 480 pt: Back, a
  CSS / JS switch, a dark editor (479 pt; in 1.172.1 an arc:// page that only says "Internal debugging pages are
  currently disabled"), and a 69 pt strip with 38 pt tools 15 pt in. From Arc's binary: the eyedropper is "Show /
  Hide Selector Picker" (ARC_BoostsEditor.bundle's SelectorPicker.js ranks selectors for the element under the pointer;
  after a click, "Copy selector for this", "Copy selector for related", "Zap all related elements"), the hammer "Show /
  Hide Developer Tools", and an arrow.clockwise "Refresh this Page" (Cra shows it for JS, which runs on load). Delete asks "Delete this Boost?" in Arc's
  dialog. Reference captures: docs/screenshots/arc-boost-*.png.

## Boosts, measured again (Arc 1.172.2, Victor's Arc on iana.org, 17 Nov 2026, #478)

- The colour wheel (BoostsEditor.ColorPicker: HueRingBackdrop, DraggablePuck, ComplementaryColorControl;
  CraCore BoostWheel): the big handle goes where it is dragged, up to 56 pt from the middle of the 133 pt
  dotted square. Its direction is the hue, clockwise from 3 o'clock (red; yellow at 6, cyan at 9, purple
  at 12), its distance the strength (236/248/236 a few points out, 193/163/81 at 56 pt toward half past 4).
  The small handle sits an eighth of a turn clockwise at the same distance in a dark shade of that hue
  (71/88/46 against the colour above) until dragged: either handle can be moved on its own and both
  change the page, the small one setting the dark pixels' hue (Arc's `secondaryHueOffset`). A 2 pt line
  joins them, and a faint circle through both shows the orbit.
  Untinted, both are grey (130 and 68) and rest 40 pt out at 3 o'clock, in the brushed grey
  frame; once tinted, the frame is a ring of every hue in the same order, not one saturation all round.
  Matched again on 27 Nov 2026 (PR #889, Elia Orsini, side-by-side screenshots of Arc's editor sampled
  pixel by pixel): the ring as 25 stops, one every 15° (`BoostWheel.ringGradient`: 235/76/57 at red,
  209/252/93 at 6, 132/249/240 at 9, 129/55/245 at 12, pre-compensated so SwiftUI's gradient lands on
  Arc's colours), a 7 pt frame with 16 pt corners over a 28 pt-cornered face, a 4 pt grid of 1 pt dots at 9.5 %
  black, the ring's colours washed over the face at 6 %, and a hairline round each handle in its own hue,
  nearly white, instead of a shadow.
- Advanced color controls: a light popover under its button, arrow up, about 224 pt wide.
- The Site Control Center's actions are Share, New Boost (a flat brush with a sparkle; tooltip "New
  Boost"), Capture and Capture Full Page. A site with boosts gets a "Boosts" section between Extensions and
  Settings ("Manage" on hover, like Extensions): one row per boost in the settings rows' style (glyph in a
  circle, name, "Enabled" or "Disabled"; grey when off). A click on the row turns it on or off and keeps
  the popover open; on hover a chevron shows at the right end, which opens that boost in the editor. The
  More menu: Clear Cache, Clear Cookies, ─, Manage Boosts…, New Boost…, ─, Manage Extensions…, Add
  Extension…. Cra keeps Copy URL in the second slot where a page can't be boosted (Arc not measured there).
- Not matched: the code editor's first click in Arc wasn't measured (Cra's now focuses it at once).

## Theme editor: the slider and the dial (Arc 1.173.1, 18 Nov 2026)

From Arc's SpaceStyleEditor code (arm64, read with objdump) and a 120 Hz, 2x screen recording of the
intensity slider dragged end to end (CraCore `SpaceStyleControls`; the app's `WaveSlider`, `GrainDial`).

- Both controls tick: Arc plays a generic haptic (`performFeedbackPattern: 0`, now, 0x1017bd8e4)
  when a value crosses a step, a multiple of the step lying between the old value and the new one,
  ends included (0x1017bcf84). The editor calls that with 0.1 for one value and 0.2 for the other
  (0x1017bcb0c, 0x1017bcd28). Which is which isn't certain from the code: the 0.2 one is held to
  0…1 first, as a turned dial needs, so Cra ticks the slider at each tenth and the dial at each fifth.
- The slider's wave is `SineWave {strength, frequency, phase}`, y = mid + strength × sin(phase +
  x × frequency / width), with strength = maxAmplitude × value (0x1017c2198): a flat line at
  nothing. In the recording it is 33.5 pt from trough to crest at full with its 5 pt line (20 pt at
  0.54, 10.5 pt at 0.2), seven waves whatever the value.
- The thumb grows with the value: held, 12.5 × 44.5 pt at nothing and 28 × 58.5 pt at full, its
  width even between (21 pt at 0.54). At rest it is a tenth smaller (22 × 50.5 pt at 0.8): under
  the pointer or held it scales to 1.1 on a spring (response 0.25, damping 0.9, 0x1017c18e4). Its
  centre travels 202.8 pt.
- Not seen: the dial turned slowly enough to count its ticks.

## Zap, measured (Arc 1.172.2, Victor's Arc on example.com, 12 Nov 2026)

- Zap on (the editor's Zap button, dark while on): the page card gets a 58 pt shelf under the page, which
  ends above it (AX: the web area shrinks; the shelf is not over the page). The shelf takes the pane's
  toolbar colour (34/34/34 on a dark page) with a 1 pt separator on top (56/56/56). It appears in one frame.
- With nothing zapped the shelf says "Click elements on the page to **Zap** them" (13 pt, Zap bold in the
  theme's tintedLight), centred between x 20 and Done. Done: 58.5 × 38 pt, 10 pt from the right, filled with
  the theme's tintedLight (250/239/198 on Victor's #F8D558), its title in the theme's ink. Done ends Zap.
- The element under the pointer: a 1 pt border in yellow 247/206/70 at 80 % and a fill that multiplies the
  page by that yellow (white text turns 247/206/70, the 36 grey background 35/29/10), 4 pt outside the
  element, 3 pt corners. Arc's overlay is native (BoostsEditorOverlayView); Cra draws it in the page.
- A click asks first, in a popover 8 pt under the highlight, 2 pt left of it and as wide (426 pt for a
  415 pt paragraph): a white-to-grey gradient (248/249/253 → 241/242/246), 14 pt corners, a row of 39 pt
  buttons 9 pt in and 9 pt apart: "Zap this" (red gradient 236/94/82 → 229/60/47), "Zap all related
  elements" (orange 240/129/87 → 233/97/46, takes the rest of the width), "Cancel" (grey 124 → 90), white
  15 pt titles. Under them a 32.5 pt footer (233/233/237): the match count and the selector in 134/134/136,
  e.g. `1  [lang="en"] [lang="zh"]` (Arc's candidates come sorted by matches, fewest first). It appears in one
  frame. All colours here were read off the display, so Cra gives them as `color(display-p3 …)`.
- "Zap this" hides the element and puts a 38 pt cell on the shelf (10 pt from the card's left edge and from
  the shelf's top; 9 pt continuous corners; tintedLight; `square.slash` 13.5 pt in the ink), followed by
  "← Click to unzap" 21.5 pt past the last cell. The editor's Zap button then shows the count instead of the bolt.
- The pointer on a cell: the cell darkens (224/213/171), the page dims (black at 36 %: 36 → 23) and the hint
  becomes a capsule 3 pt past the cells, 28.5 pt tall, in the theme's ink, reading "**Restore** <selector>".
- A click on a cell unzaps at once, no question (the count drops). Arc 1.172.2 left the element hidden until a
  reload; Cra shows it again at once.
- Not measured: the gap between two cells (Arc stopped answering the pointer in Zap after AX presses; Cra uses
  8 pt), what Arc does when the shelf runs out of room (its IndividualZapCell has overflow controls), and the
  shelf in a light page's colours (Cra follows the toolbar colour and flips its text and separator).

## Previews, measured (Arc 1.172.1, Victor's signed-in Arc, 8 Nov 2026)

- Hovering a favorite that isn't the open tab shows the card about 0.25 s after the tile lights up (once the content is
  in hand; the first Gmail fetch took ~0.85 s); it grows from about 80 % and fades in over some 4 frames at 60 fps
  (opacity .21/.47/.76/.95/1). The pointer can move onto the card; once it has left tile and card, the card waits
  ~0.17 s and fades out, shrinking a little, over ~4 frames. Cra measured the same way: 0.28 s, .14/.29/.82/.97/1,
  0.15 s (CraCore FavoritePreviewMotion).
- Gmail: 238 pt wide, at most 270 pt (the fourth row peeks), rows 84 pt with 1 pt lines, 11 pt insets; sender semibold
  13 and its age ("50s", "1m", "3h"), subject 13, two grey lines 12; the pointer's row a lighter card 3 pt in; a 32 pt ＋
  9.5 pt from the bottom right. The card refreshes in place when mail arrives.
- Calendar: 238 × 255 pt, an hour 42 pt with "8 AM" (English, whatever the Mac's clock) at the top left, the current
  hour's line 13 pt under the top, a cream now line with a dot from 42 pt in, a filled gear and a ＋ at the bottom right.
  Gear: "Last fetch: Just now" (dimmed), Refresh, Disable Live Calendar. The favorite's menu starts with Live Calendar ▸:
  status, Refresh, ✓Show Hover Preview, ✓Show Time to Next Meeting, Show Next Meeting Link ▸ Never / On Start /
  ✓Two Minutes Before / Five / Ten. Arc's LiveCalendarClient (a hidden browser) says "Failed to update" for a calendar
  with events, so its event blocks, countdown and meeting link couldn't be seen: Cra's are its own, in the card's style.
  Cra reads the primary calendar the way Google's Calendar embed does (a hidden `calendar/u/<n>/embed` page asks the
  Calendar API through the page's own signed-in client), every 5 minutes and on hover when older than a minute.

## Library, measured (Arc 1.172.1, Victor's Arc, 8 Nov 2026)

- Media preview (MediaPreviewWindow): a pick doesn't leave the Library; a panel 199 pt in from the
  window's sides and 133 pt from top and bottom (1728 × 1084 pt window) grows out of the thumbnail in
  ~0.21 s, ghosting as it goes, over the window dimmed by about half. A 46 pt header: ✕, ‹ ›, the name
  and its age, then ⋯ and "Open in Preview ↗"; the picture fits 15 pt inside, over a blurred copy of
  itself. Cra: CraCore MediaPreview, Esc/← →/Space, ⋯ = Open, Show in Finder, Copy, Move to Trash.
- No ⋯ beside the search on Media and Boosts; the first item starts 15 pt (a media tile) or 10.5 pt
  (a boost's card) under the search field.
- Easels page: the media grid's tiles, two to a row, newest first, no day headers and no ⋯; each a light
  card (white 3 pt rim) with the easel drawn small, Arc's pink squiggle and the title in bold at its
  bottom left; right-click Delete (Cra asks first). Arc's "Your Easels are yours to keep / Export All
  Easels" banner is about Arc winding down and is *skip*.
- Easel pictures resize from their corners and keep their proportions, the opposite corner fixed
  (watched in Arc 8 Nov: 163 × 133 → 216 × 175 pt). A picked picture or shape has a square 2 pt outline
  on its edge (#7FB8D6) and a 7.5 pt ring with a 3 pt dark dot at each corner. Cra: CraCore Easel.resized, the diagonal resize
  cursors on a picked item's corners; rectangles and ellipses resize freely (⇧ keeps proportions).
- An easel picked on the Easels page opens in Peek (no toolbar, the canvas on #0B0B0B, only ✕ and ⤢;
  ⤢ makes it a tab with the veiled backdrop).
- A Peek with the address in the sidebar (Arc 1.174, checked live by the reporter of GitHub #648, 20 Nov
  2026): the card has no bar; the sidebar's address field shows the Peek's page while it is in front, and
  its ← → ↻, the field (command bar or edit in place) and Copy Link act on the Peek. Closing the Peek or
  showing another tab gives the field back to the tab. With the toolbar shown the card keeps its 32 pt bar
  (Arc 1.171). Cra: CraCore `PeekAddress`; scenarios peek-sidebar-address and peek-card-bar-with-toolbar.
  Cra's own: #493's "Hide the Peek toolbar until you need it" keeps a bar that slides in either way, and
  while the field shows a Peek it offers only Copy Link (pins and the Site Control Center are the tab's).
- Media grid: in a 305 pt column the tiles are 132 pt, 12 pt from the left, 16 pt apart, rows 8 pt
  apart; a video has a white ▶ over its picture.
- Downloads and Archived Tabs: a "Filter" pill (73 × 36 pt) beside the search opens a panel in its
  place: "Filter Archived Tabs" / "Filter Downloads…" and Done, then chips (Archived Tabs: How was the
  tab closed? Auto-Closed / Manually Closed; Where was the tab? Little Arc and each space. Downloads:
  Profiles); a picked chip is dark with white text. An archived row on hover shows a bin (remove) and
  a curved arrow (restore). Downloads' empty page: "Come back after you've found some cool stuff to
  save." Cra's Open Downloads Folder and Clear Archive moved to the rail buttons' right-click.
- A media pick's menu (its tile's right-click and the preview's ⋯): Copy Image, —, Send via iMessage,
  AirDrop, —, Show in Finder, —, Hide from Arc (Cra: "Hide from Cra"; the file stays on disk).
- The selected rail page's glyph and the Spaces page's + take the space's colours (an olive space: a
  cream disc with a dark mark), not a fixed blue.
- An easel's tile under the pointer (Arc 1.173.1, a 120 Hz screen recording read frame by frame,
  17 Nov 2026): the tile grows about its centre from 128.6 to 136.3 pt (× 1.06; the edges read to
  about ± 0.5 px, so 1.0625 nearly fits too) in 0.1 s, fast first with no overshoot, and its backing
  stands twice as far from the sidebar's colour; the same way back when the pointer leaves. Cra:
  CraCore EaselTileHover; the list leaves the top row's tiles room to grow. Not found in Arc's binary:
  the constant itself (its code holds 1.06 once, in an unrelated angle).
- Boost rows: the site's icon on a 43 pt light tile with a white rim, name 14 pt over the site; under
  the pointer a rounded card and a 36 × 22 pt switch; off = the tile struck through; right-click
  Rename (in place), Delete.

## Library from a hidden sidebar, measured (Arc 1.173.1, 18 Nov 2026)

Read frame by frame from a 120 Hz, 2x screen recording: a 250 pt sidebar hidden and out over the
page, 6 pt inside the window, and a 405 pt Library (CraCore `LibrarySwipe`, "From a hidden
sidebar"; the app's `MainWindowController`, `FloatingSidebarController.retreat`).

- With the sidebar hidden and out over the page, a swipe right on the first space brings the
  Library in docked, as from a docked sidebar. It slides in from the window's edge, under the
  floating sidebar, and pushes the page before it at the page's full width (the Google logo moved
  802 px for an 810 px Library).
- The floating sidebar goes back out toward the window's edge as the Library comes, two points for
  every three the page moves: the page's shift over the sidebar's was 1.43 to 1.53 in twelve frames
  (322 px for 211, 144 for 97). Its rows don't fade. The Library shows in the gap between the two
  from about 0.4 of the way.
- Swiping back before lifting brings the floating sidebar and the page back the same way.
- Landed, the Library is docked with the window's buttons, and the floating sidebar is gone.
- Leaving the Library by a swipe slides it out to the left with the page following, and ends on the
  hidden sidebar; the floating sidebar doesn't show on the way. It comes out again under the pointer
  as it always does.
- A window with one space swipes into the Library the same way.
- Not measured: another sidebar width (the two-for-three could be a share of the Library's width,
  as taken here, or the sidebar's own width and margin, which is 256 against 270 pt here), a
  sidebar on the right, and a mouse's back button over the floating sidebar (Cra takes it the same
  way in).

## Little Arc from a link in another app, measured (Arc 1.173.1, Victor's Arc, 20 Nov 2026)

Measured with a probe app that clicks a link the way Slack does (LaunchServices, `NSWorkspace.open` with Arc's
app), with its own window just over Arc's main window, sampling the window server's order every 2 ms. Arc's
main window was on the left display, and Little Arc opened on the main one.

| Arc | Cra |
|---|---|
| Arc's main window rose over the other app's window 0.5 s after the click and stayed in front; Little Arc came up on the other display 1.2 s later | *Deviation, Victor 20 Nov 2026 (GitHub #607):* the browser windows stay behind the app the link came from. macOS raises Cra's main window as Cra comes forward for the link; it goes back as soon as the link arrives, before the Little Window shows (`LittleWindowRaise`, `BrowserWindowsBehind`; scenario little-window-leaves-browser). Before the fix it stayed in front, as in Arc |

## Left for later, and why

