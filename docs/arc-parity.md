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
| Boosts (per-site CSS/JS, colours, fonts, Zap) | URL bar ✎, Library ▸ Boosts, Settings ▸ Advanced "Enable Boosts" | done | New Boost (command bar), the editor (wheel, invert, contrast/brightness/saturation, 20 fonts, size, case, Zap with its confirm popover and the shelf of zapped elements under the page (click one to unzap; "Zap, measured" below), CSS/JS code), Library ▸ Boosts, Settings ▸ Advanced switch. The Code panel's eyedropper (selector picker: outlines the element and the ones like it, then Copy selector for this / for related, Zap all related elements), hammer (Show / Hide Developer Tools) and, for JS, Refresh this Page. The Boost Gallery and sharing are *skip* (arc.net). The colour wheel's recolouring is CSS filters, not Arc's own engine. |
| Easels | File ▸ New Easel ⌃⇧E, Library ▸ Easels | partial | File ▸ New Easel (⌃⇧E): canvas, title, Pointer/Image/Text/Ellipse/Rectangle/Arrow/Freehand, pictures by file, paste or drop, saved per easel. Library ▸ Easels and Window ▸ View Easels… done. The canvas shows the window's backdrop under a 50 % veil as in Arc. The toolbar strip above it takes the same veil. The capture menu's New Easel done. The capture menu's Send To… done too. The pill's + and − and Aa (Arc's four looks: bold, serif, wide, mono, in macOS's designs) work, on the title too; Duplicate (the toolbar's eighth button) done; sharing is *skip* (cloud). |
| Notes | File ▸ New Note ⌃⇧N, ⌃⌥N in split, Help ▸ Export Arc Notes | *skip* | Arc 1.172.1 no longer creates Notes: New Note is gone from the File menu and ⌃⇧N does nothing; only Help ▸ Export Arc Notes is left. |
| Library ▸ Media | Window ▸ View Media…, Library rail | done | Off until Show Media; right-click the rail's Media button for the folders (Cra has no captures folder). A pick opens Arc's preview over the dimmed window (see "Library, measured"); the Library stays open. |
| Essential Keyboard Shortcuts window | Help ▸ Essential Keyboard Shortcuts, Settings ▸ Shortcuts | done | 475×462 floating dark panel, five rows of key caps, "View All ↗". |
| Appearance | View ▸ Appearance ▸ Automatic / Light / Dark ("Websites, Easels, and Notes will use:"); command bar "Switch to Light Mode" / "Switch to Dark Mode" / "Switch to Automatic Appearance" | done | Forces prefers-color-scheme for pages and, as in Arc, the browser's own appearance: windows, menus, command bar, Auto space themes (#362). |
| Stay On Top | Window ▸ Stay On Top | done | Floats the window above other apps. |
| Save Page As | File ▸ Save Page As ⇧⌘S | done | |
| File menu: Share…, New Profile, Arc's sections | File ▸ Share…, File ▸ New Profile | done | GitHub #279: the File menu has Arc 1.172.1's five sections and rows (FileMenu); Share… opens the system share list under the toolbar, New Profile the New Profile dialog; Close Tab shows only with a tab selected; New Space… moved to Spaces, New Folder… to Tabs. |
| Capture Full Page / Portrait Mode | File, URL-bar menu | done | Portrait: 390 × 844 pt at 3x. |
| Copy URL without trackers | Copy URL ⇧⌘C ("Copy the current tab's URL without trackers") | done | utm_* and click ids dropped (CleanURL). |
| Menu on several picked tabs | ⌘/⇧-click tabs, right-click one | done | Arc 1.17x's rows, read over AX (PickedTabsMenu, #356): Copy Links, Share N Items… \| Change Icon… (dimmed), Mute \| Open in Split View (dimmed past four), Duplicate, Move to ▸ (spaces, New Space…), New Folder with N Items \| Archive Tabs (pinned picks too), Archive Tabs Below (dimmed, Today rows only); with an Easel among the picks the short menu ending in Archive Items. Share asks first with Arc's "Send this Folder to anyone, on any browser." sheet (AppDialog.shareLink), as Share Folder… now does. |
| Copy URL as Quote | Edit ▸ ⌃⇧⌘C, "Enable Shared Quotes when highlighting text" | done | Arc links to arc.net (cloud); Cra copies a text-fragment link. |
| AppleScript dictionary | Arc.sdef, View ▸ Developer ▸ Allow JavaScript from Apple Events | done | Arc's terms and codes (resources/Cra.sdef); `execute javascript` only after View ▸ Developer ▸ Allow JavaScript from Apple Events (off by default, as in Arc). |
| Cast | View ▸ Cast | done | Chrome's Cast bubble (IDC_ROUTE_MEDIA). |
| Page translation | Toolbar `character.bubble`, URL field "Translation Available", popover | done | GitHub #310: Arc's button (left of the sliders), the URL field's line with the toolbar hidden, the popover (Options: Choose Another Language ▸, Never Translate This Site, Language Settings; Translate / Show Original) and its toasts, on Chromium's translate state instead of Chrome's bubble (scripts/cef-patches/translate-ui.patch). Never Translate This Site uses Chromium's per-profile list, not Arc's `translateNeverHosts`; Settings ▸ Advanced "Reset Translated-site Prompts" is not in Cra yet. |
| Find and Replace, Use Selection to Find, Jump to Selection | Edit ▸ Find | done | Use Selection to Find and Jump to Selection (⌘J) done. *skip*: Find and Replace (⌥⌘F). Checked live in Arc 1.172.2 on 11 Nov: it does nothing anywhere Cra has a counterpart. In an Easel text box with the caret in it, the whole Find submenu is off and ⌥⌘F does nothing; on a web page Find… is on but Find and Replace stays off. It was for Notes, which Arc 1.172 no longer has. |
| Sound effects | Settings ▸ Advanced "Play Arc sound effects" | done | Settings ▸ Advanced ▸ Play Cra sound effects gates the capture shutter. |
| Theme data for websites | Settings ▸ Advanced "Allow websites to get your theme data" | done | `--arc-palette-*` and `--arc-background-*` as #RRGGBBAA, from the space's theme (ArcThemeData; fitted to Arc's stored palette, checked live). |
| Window dragging from the top of webpages | Settings ▸ Advanced | done | An ordinary-arrow drag that starts within 60 pt of the card's top, its bar included, moves the window: the top 60 pt of the page with the toolbar hidden, 28 pt under the toolbar (Arc measured side by side, #363). Text, link and resize cursors keep their gesture; the rightmost 14 pt stay with the page and its scrollbar. The press reaches the page immediately, the first drag event moves the window, and the page gets the release, so a slipped click still clicks (WindowContentGrabber, PageTopDrag). Settings ▸ Advanced, on by default as in Arc. |
| Restore windows from previous session | Settings ▸ Advanced | done | Settings ▸ Advanced; off keeps the window in use last. |
| Block Cookie Banners | Settings ▸ General | done | Settings ▸ Privacy; hides the common consent managers' banners (CookieBanners), off by default as in Arc. |
| Archive Little Arcs after | Settings ▸ Links (6 hours default) | done | Settings ▸ Tabs ▸ Links; a Little Window left alone that long closes into the archive. |
| Previews (Gmail, Calendar on Favorites) | Settings ▸ General ▸ Previews Settings…, a Calendar favorite's menu ▸ Live Calendar | done | Gmail: the unread mail from Gmail's Atom feed (the space's own sign-in) in Arc's card, rows, ＋ and motion, measured on Victor's signed-in Arc 8 Nov. Calendar: Arc's timeline card, gear menu, Live Calendar ▸ submenu, tile countdown and meeting link; events read through Google's Calendar embed (Arc's own fetch says "Failed to update" in 1.172.1). See "Previews, measured". |
| Join Meeting ⌃⌘J | Shortcuts | done | The call on now, else the next one today, from a Live Calendar favorite. |
| Music notes on a playing favorite | A favorite on a music site, while it plays | done | Core Animation notes rise from the playing icon's top edge and stop when the sound pauses. As in Arc 1.172.2 (live, 11–12 Nov 2026) they keep floating on a muted tab and with Reduce Motion on. Compared side by side with Arc in full windows at 1x and 2x, light and dark spaces, top row and lower rows; light notes use 30% black, dark notes 80% white. |
| Troubleshooting menu | Help ▸ Troubleshooting: Record Trace, Open Task Manager, Reveal Arc Data, Copy Arc Info | done | Export Diagnostics…, Open Task Manager (Chrome's), Reveal Cra Data, Copy Cra Info; Record Trace is Arc-internal. |
| Help menu | Getting Started, Release Notes, Contact the Team, Visit Help Center, Restore Data | done | Cra Help (Arc's Help Center and Getting Started guide), Release Notes, Report an Issue… (Contact the Team), Essential Keyboard Shortcuts, Troubleshooting ▸ Task Manager / Reveal Data / Copy Info. *skip*: Restore Data and Export Arc Notes (Arc's account and Notes), Record Trace (chrome://tracing is a developer tool). |
| Ad blocker upsell card, Sync, Account, Membership card, Share Arc, Sign Out, Send to Dia, Share Space | | *skip* | Account/cloud. |
| Max: 5-Second Previews | Settings ▸ Max | done | Arc's hover cards on the Mac's Apple Intelligence: Arc's links on Google, X and Hacker News, or Shift on any link (the small card within the site); Arc's prompt, card, timing and share menu (arc-reverse-engineering.md). |
| Max: Instant Links, ChatGPT in the Command Bar, New ChatGPT Message ⌥⌘G | Settings ▸ Max | *skip* | Cloud AI partners. Tidy Tabs/Titles/Downloads/5-Second Previews on-device. |

## 2. Menu bar and shortcuts

Arc's actions (Settings ▸ Shortcuts, 106 rows) that Cra has no action for:

| Arc action | Arc shortcut | Cra |
|---|---|---|
| Collapse Pinned Tabs (View) | — | done |
| Reveal Tab in Sidebar (Tabs) / Reveal Current Tab | ⌃Space | done |
| Reset all tabs in this Space (Tabs) | — | done |
| View Archive… / Clear Archive (Archive menu) | — | done |
| Collapse All Folders / Expand All Folders | — | done |
| Next Tab / Previous Tab, second binding | ⌘} / ⌘{ | done |
| Go Back / Go Forward, second binding | ⌘← / ⌘→ | done | Bound since the first build; as in Chrome they act only when the page leaves the key alone (a text field keeps ⌘← for the line start). |
| Developer Tools, second binding | F12 | done |
| Go to last Sidebar Item | ⌘9 | done |
| Switch to Split View 1–4 | ⌃⇧1…4 | done |
| Expand Current Split | — | done | View ▸ Expand Current Split and the command bar ("expand", "maximize"), no default shortcut, as in Arc 1.172.2 (measured live 11 Nov 2026, docs/arc-reverse-engineering.md "Expand Current Split"). The focused pane takes the window and the others keep the 220 pt minimum, stored as width factors 1 and 0; laid out in one frame. Cra's pane minimum went from 200 to Arc's 220 pt with it. |
| Open Extensions | ⌘E | done |
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
| Today tab | all done (Share ▸, Change Icon…, Open in Split View, Archive Tabs Below) |
| Pinned tab | Edit Pinned Page ▸ (Cra lists them flat on purpose, PR #55), Remove Pin (Share ▸, Change Icon… and Add Split View done) |
| Space header / empty sidebar | Share Space… (*skip*), New Folder, Manage Spaces…, Delete Space (check order) |
| Folder | Paste as New Tab, Move to ▸, Duplicate, Turn "…" into Space, Copy All Links, and Arc's order (New Nested Folder… is Cra's New Folder Inside). Share Folder… done (GitHub #357): Arc stored the folder on arc.net; Cra's crabrowser.app/folder link carries it after the # (FolderShareLink), so nothing is stored and the server never sees it. Same toast, "Copied Folder URL", after Arc's "Send this Folder to anyone" warning (AppDialog.shareLink, #356) |
| Toolbar address | Share ▸ (in the Site Control Center), Disable Shared Quotes (arc.net); the rest done. Blocked pop-ups (GitHub #357): Arc keeps Chromium's list (hasBlockedPopUp, showBlockedPopups) but its button wasn't seen yet; Cra shows Chrome's crossed-out window before the sliders, or "Pop-ups Blocked" under the sidebar's address, with Chrome's list and Always Allow as a menu |
| Library button | Show media ▸ Documents, Desktop, Screenshots, Arc Captures, Downloads |

## 4. Settings

| Arc tab | Rows Cra lacks |
|---|---|
| General | (Previews: Gmail done, Tabs pane; Live Calendar in the Calendar favorite's menu, as in Arc; Block Cookie Banners done, under Privacy) |
| Profiles | "New documents" app (Arc's Notes/Easels); Privacy, Passwords, Credit Cards and Notifications done |
| Links | "Open Little Arc when clicking on links with ⌥⌘ held"; Archive Little Windows after done |
| Advanced | Shared Quotes (arc.net) (the rest done) |
| Icon | Cra has its own icon picker |

## 5. Animations and styling

- Command bar (⌘T / File ▸ New Tab…), 7 Nov 2026, 57 fps region recordings of both apps: Arc's bar is
  there complete from one frame to the next, no fade or scale; Cra's too. Matches.

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
- Boost rows: the site's icon on a 43 pt light tile with a white rim, name 14 pt over the site; under
  the pointer a rounded card and a 36 × 22 pt switch; off = the tile struck through; right-click
  Rename (in place), Delete.

## Left for later, and why

