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
| Boosts (per-site CSS/JS, colours, fonts, Zap) | URL bar ✎, Library ▸ Boosts, Settings ▸ Advanced "Enable Boosts" | missing | Biggest local feature still absent. |
| Easels | File ▸ New Easel ⌃⇧E, Library ▸ Easels | partial | File ▸ New Easel (⌃⇧E): canvas, title, Pointer/Image/Text/Ellipse/Rectangle/Arrow/Freehand, pictures by file, paste or drop, saved per easel. Library ▸ Easels and Window ▸ View Easels… done. The canvas shows the window's backdrop under a 50 % veil as in Arc. Missing: the toolbar strip above it stays white (Arc's blends into the canvas), the text-size pill, captures into an easel; sharing is *skip* (cloud). |
| Notes | File ▸ New Note ⌃⇧N, ⌃⌥N in split, Help ▸ Export Arc Notes | *skip* | Arc 1.172.1 no longer creates Notes: New Note is gone from the File menu and ⌃⇧N does nothing; only Help ▸ Export Arc Notes is left. |
| Library ▸ Media | Window ▸ View Media…, Library rail | done | Off until Show Media; ⋯ picks the folders (Cra has no captures folder). |
| Essential Keyboard Shortcuts window | Help ▸ Essential Keyboard Shortcuts, Settings ▸ Shortcuts | done | 475×462 floating dark panel, five rows of key caps, "View All ↗". |
| Website appearance | View ▸ Appearance ▸ Automatic / Light / Dark ("Websites, Easels, and Notes will use:") | done | Forces prefers-color-scheme for pages. |
| Stay On Top | Window ▸ Stay On Top | done | Floats the window above other apps. |
| Save Page As | File ▸ Save Page As ⇧⌘S | done | |
| Capture Full Page / Portrait Mode | File, URL-bar menu | done | Portrait: 390 × 844 pt at 3x. |
| Copy URL without trackers | Copy URL ⇧⌘C ("Copy the current tab's URL without trackers") | done | utm_* and click ids dropped (CleanURL). |
| Copy URL as Quote | Edit ▸ ⌃⇧⌘C, "Enable Shared Quotes when highlighting text" | done | Arc links to arc.net (cloud); Cra copies a text-fragment link. |
| AppleScript dictionary | Arc.sdef, View ▸ Developer ▸ Allow JavaScript from Apple Events | missing | Raycast and other launchers script Arc through it. |
| Cast | View ▸ Cast | done | Chrome's Cast bubble (IDC_ROUTE_MEDIA). |
| Find and Replace, Use Selection to Find, Jump to Selection | Edit ▸ Find | partial | Use Selection to Find and Jump to Selection (⌘J) done; Find and Replace is for Arc's Notes/Easels text, which Cra doesn't have. |
| Sound effects | Settings ▸ Advanced "Play Arc sound effects" | done | Settings ▸ Advanced ▸ Play Cra sound effects gates the capture shutter. |
| Theme data for websites | Settings ▸ Advanced "Allow websites to get your theme data" | done | `--arc-palette-*` and `--arc-background-*` as #RRGGBBAA, from the space's theme (ArcThemeData; fitted to Arc's stored palette, checked live). |
| Window dragging from the top of webpages | Settings ▸ Advanced | measured | With the toolbar hidden, Arc drags the window from the top 56 pt of the page (66 pt below the window's top); 58 pt in, the page gets the drag. Cra's strip reaches 4 pt into the page. Needs clicks in that band held until the pointer moves, across Chromium's page windows. |
| Restore windows from previous session | Settings ▸ Advanced | done | Settings ▸ Advanced; off keeps the window in use last. |
| Block Cookie Banners | Settings ▸ General | missing | Cra blocks ads and trackers only. |
| Archive Little Arcs after | Settings ▸ Links (6 hours default) | done | Settings ▸ Tabs ▸ Links; a Little Window left alone that long closes into the archive. |
| Previews (Gmail, Calendar on Favorites) | Settings ▸ General ▸ Previews Settings… | missing | Fetches through the browser session; nothing leaves the Mac. |
| Join Meeting ⌃⌘J | Shortcuts | missing | Needs calendar previews first. |
| Troubleshooting menu | Help ▸ Troubleshooting: Record Trace, Open Task Manager, Reveal Arc Data, Copy Arc Info | done | Export Diagnostics…, Open Task Manager (Chrome's), Reveal Cra Data, Copy Cra Info; Record Trace is Arc-internal. |
| Help menu | Getting Started, Release Notes, Contact the Team, Visit Help Center, Restore Data | partial | |
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
| Go Back / Go Forward, second binding | ⌘← / ⌘→ | missing |
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
| General | Previews Settings…, Block Cookie Banners |
| Profiles | "New documents" app (Arc's Notes/Easels); Privacy, Passwords, Credit Cards and Notifications done |
| Links | "Open Little Arc when clicking on links with ⌥⌘ held"; Archive Little Windows after done |
| Advanced | window dragging from the top of webpages (measured), Shared Quotes (arc.net), Enable Boosts (sound effects, restore windows and theme data done) |
| Icon | Cra has its own icon picker |

## 5. Animations and styling

Not re-measured in this sweep: earlier sessions measured the sidebar, command bar, split view,
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

## Left for later, and why

- Boosts: the offline Arc has no network and a local server is blocked in this session, so its Boost
  editor couldn't be put on screen to copy. Needs a site in Arc (Victor's OK to run the real Arc, or
  a localhost server).
- AppleScript dictionary (a new way for other apps to drive Cra; worth a decision on what it may do,
  as for cra:// URLs), cookie banner blocking, window dragging from the top of pages (measured, above), Previews and
  Join Meeting: not started.
