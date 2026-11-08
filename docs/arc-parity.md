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
| Boosts (per-site CSS/JS, colours, fonts, Zap) | URL bar ✎, Library ▸ Boosts, Settings ▸ Advanced "Enable Boosts" | done | New Boost (command bar), the editor (wheel, invert, contrast/brightness/saturation, 20 fonts, size, case, Zap, CSS/JS code), Library ▸ Boosts, Settings ▸ Advanced switch. The Code panel's eyedropper (selector picker: outlines the element and the ones like it, then Copy selector for this / for related, Zap all related elements), hammer (Show / Hide Developer Tools) and, for JS, Refresh this Page. The Boost Gallery and sharing are *skip* (arc.net). The colour wheel's recolouring is CSS filters, not Arc's own engine. |
| Easels | File ▸ New Easel ⌃⇧E, Library ▸ Easels | partial | File ▸ New Easel (⌃⇧E): canvas, title, Pointer/Image/Text/Ellipse/Rectangle/Arrow/Freehand, pictures by file, paste or drop, saved per easel. Library ▸ Easels and Window ▸ View Easels… done. The canvas shows the window's backdrop under a 50 % veil as in Arc. The toolbar strip above it takes the same veil. The capture menu's New Easel done. The capture menu's Send To… done too. The pill's + and − and Aa (Arc's four looks: bold, serif, wide, mono, in macOS's designs) work, on the title too; Duplicate (the toolbar's eighth button) done; sharing is *skip* (cloud). |
| Notes | File ▸ New Note ⌃⇧N, ⌃⌥N in split, Help ▸ Export Arc Notes | *skip* | Arc 1.172.1 no longer creates Notes: New Note is gone from the File menu and ⌃⇧N does nothing; only Help ▸ Export Arc Notes is left. |
| Library ▸ Media | Window ▸ View Media…, Library rail | done | Off until Show Media; ⋯ picks the folders (Cra has no captures folder). |
| Essential Keyboard Shortcuts window | Help ▸ Essential Keyboard Shortcuts, Settings ▸ Shortcuts | done | 475×462 floating dark panel, five rows of key caps, "View All ↗". |
| Website appearance | View ▸ Appearance ▸ Automatic / Light / Dark ("Websites, Easels, and Notes will use:") | done | Forces prefers-color-scheme for pages. |
| Stay On Top | Window ▸ Stay On Top | done | Floats the window above other apps. |
| Save Page As | File ▸ Save Page As ⇧⌘S | done | |
| Capture Full Page / Portrait Mode | File, URL-bar menu | done | Portrait: 390 × 844 pt at 3x. |
| Copy URL without trackers | Copy URL ⇧⌘C ("Copy the current tab's URL without trackers") | done | utm_* and click ids dropped (CleanURL). |
| Copy URL as Quote | Edit ▸ ⌃⇧⌘C, "Enable Shared Quotes when highlighting text" | done | Arc links to arc.net (cloud); Cra copies a text-fragment link. |
| AppleScript dictionary | Arc.sdef, View ▸ Developer ▸ Allow JavaScript from Apple Events | done | Arc's terms and codes (resources/Cra.sdef); `execute javascript` only after View ▸ Developer ▸ Allow JavaScript from Apple Events (off by default, as in Arc). |
| Cast | View ▸ Cast | done | Chrome's Cast bubble (IDC_ROUTE_MEDIA). |
| Find and Replace, Use Selection to Find, Jump to Selection | Edit ▸ Find | partial | Use Selection to Find and Jump to Selection (⌘J) done; Find and Replace is for Arc's Notes/Easels text, which Cra doesn't have. |
| Sound effects | Settings ▸ Advanced "Play Arc sound effects" | done | Settings ▸ Advanced ▸ Play Cra sound effects gates the capture shutter. |
| Theme data for websites | Settings ▸ Advanced "Allow websites to get your theme data" | done | `--arc-palette-*` and `--arc-background-*` as #RRGGBBAA, from the space's theme (ArcThemeData; fitted to Arc's stored palette, checked live). |
| Window dragging from the top of webpages | Settings ▸ Advanced | done | With the toolbar hidden, a drag from the top 56 pt of a page moves the window; a click there still reaches the page (PageTopDrag). Settings ▸ Advanced, on by default as in Arc. |
| Restore windows from previous session | Settings ▸ Advanced | done | Settings ▸ Advanced; off keeps the window in use last. |
| Block Cookie Banners | Settings ▸ General | done | Settings ▸ Privacy; hides the common consent managers' banners (CookieBanners), off by default as in Arc. |
| Archive Little Arcs after | Settings ▸ Links (6 hours default) | done | Settings ▸ Tabs ▸ Links; a Little Window left alone that long closes into the archive. |
| Previews (Gmail, Calendar on Favorites) | Settings ▸ General ▸ Previews Settings…, a Calendar favorite's menu ▸ Live Calendar | done | Gmail: the unread mail from Gmail's Atom feed (the space's own sign-in) in Arc's card, rows, ＋ and motion, measured on Victor's signed-in Arc 8 Nov. Calendar: Arc's timeline card, gear menu, Live Calendar ▸ submenu, tile countdown and meeting link; events read through Google's Calendar embed (Arc's own fetch says "Failed to update" in 1.172.1). See "Previews, measured". |
| Join Meeting ⌃⌘J | Shortcuts | done | The call on now, else the next one today, from a Live Calendar favorite. |
| Troubleshooting menu | Help ▸ Troubleshooting: Record Trace, Open Task Manager, Reveal Arc Data, Copy Arc Info | done | Export Diagnostics…, Open Task Manager (Chrome's), Reveal Cra Data, Copy Cra Info; Record Trace is Arc-internal. |
| Help menu | Getting Started, Release Notes, Contact the Team, Visit Help Center, Restore Data | done | Cra Help (Arc's Help Center and Getting Started guide), Release Notes, Report an Issue… (Contact the Team), Essential Keyboard Shortcuts, Troubleshooting ▸ Task Manager / Reveal Data / Copy Info. *skip*: Restore Data and Export Arc Notes (Arc's account and Notes), Record Trace (chrome://tracing is a developer tool). |
| Ad blocker upsell card, Sync, Account, Membership card, Share Arc, Sign Out, Send to Dia, Share Space | | *skip* | Account/cloud. |
| Max: Instant Links, 5-Second Previews, ChatGPT in the Command Bar, New ChatGPT Message ⌥⌘G | Settings ▸ Max | *skip* | AI partner (cloud). Tidy Tabs/Titles/Downloads already on-device. |

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
| Expand Current Split | — | missing (Cra has Flip orientation) |
| Open Extensions | ⌘E | done |
| Show Little Arc "Open In" Menu | ⇧⌘O | done |
| Open Little Arc or Peek in… | ⌘O | partial (Window menu) |
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
| Toolbar address | Share ▸ (in the Site Control Center), Disable Shared Quotes (arc.net); the rest done |
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

Not re-measured in this sweep: earlier sessions measured the command bar, split view,
Peek, Little Arc, PiP, folders, space dock, Library swipe, dialogs, toasts and toolbar against Arc
(docs/arc-reverse-engineering.md). New surfaces built from this list are matched to captures taken
in this sweep (Essential Shortcuts window, Library pages).

## Built in this sweep

- Window ▸ Stay On Top; File ▸ Capture Full Page and Save Page As (⇧⌘S, single file or HTML only);
  Edit ▸ Copy URL as Quote (⌃⇧⌘C, a text-fragment link instead of Arc's arc.net card).
- Copy URL, Copy URL as Markdown and the sidebar's Copy Link leave out utm_* and click ids
  (CleanURL).
- View ▸ Collapse/Expand Pinned Tabs; View ▸ Appearance (Automatic / Light / Dark for websites).
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

## Left for later, and why

