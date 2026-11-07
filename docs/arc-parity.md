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
| Easels | File ▸ New Easel ⌃⇧E, Library ▸ Easels | missing | Canvas of captures, text and live page clips. |
| Notes | File ▸ New Note ⌃⇧N, ⌃⌥N in split, Help ▸ Export Arc Notes | missing | Rich-text documents as sidebar items. |
| Library ▸ Media | Window ▸ View Media…, Library rail | missing | Images/videos from Documents, Desktop, Screenshots, Arc Captures, Downloads; right-click "Show media" picks folders. |
| Essential Keyboard Shortcuts window | Help ▸ Essential Keyboard Shortcuts, Settings ▸ Shortcuts | done | 475×462 floating dark panel, five rows of key caps, "View All ↗". |
| Website appearance | View ▸ Appearance ▸ Automatic / Light / Dark ("Websites, Easels, and Notes will use:") | done | Forces prefers-color-scheme for pages. |
| Stay On Top | Window ▸ Stay On Top | done | Floats the window above other apps. |
| Save Page As | File ▸ Save Page As ⇧⌘S | done | |
| Capture Full Page / Portrait Mode | File, URL-bar menu | partial | Capture Full Page done; Portrait Mode missing. |
| Copy URL without trackers | Copy URL ⇧⌘C ("Copy the current tab's URL without trackers") | done | utm_* and click ids dropped (CleanURL). |
| Copy URL as Quote | Edit ▸ ⌃⇧⌘C, "Enable Shared Quotes when highlighting text" | done | Arc links to arc.net (cloud); Cra copies a text-fragment link. |
| AppleScript dictionary | Arc.sdef, View ▸ Developer ▸ Allow JavaScript from Apple Events | missing | Raycast and other launchers script Arc through it. |
| Cast | View ▸ Cast | missing | Chromium's media router. |
| Find and Replace, Use Selection to Find, Jump to Selection | Edit ▸ Find | missing | |
| Sound effects | Settings ▸ Advanced "Play Arc sound effects" | done | Settings ▸ Advanced ▸ Play Cra sound effects gates the capture shutter. |
| Theme data for websites | Settings ▸ Advanced "Allow websites to get your theme data" | missing | Arc exposes the space's palette to pages. |
| Window dragging from the top of webpages | Settings ▸ Advanced | missing | |
| Restore windows from previous session | Settings ▸ Advanced | partial | Cra has "Quit and Keep Windows" only. |
| Block Cookie Banners | Settings ▸ General | missing | Cra blocks ads and trackers only. |
| Archive Little Arcs after | Settings ▸ Links (6 hours default) | missing | |
| Previews (Gmail, Calendar on Favorites) | Settings ▸ General ▸ Previews Settings… | missing | Fetches through the browser session; nothing leaves the Mac. |
| Join Meeting ⌃⌘J | Shortcuts | missing | Needs calendar previews first. |
| Troubleshooting menu | Help ▸ Troubleshooting: Record Trace, Open Task Manager, Reveal Arc Data, Copy Arc Info | partial | Cra has Export Diagnostics… |
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
| Show Little Arc "Open In" Menu | ⇧⌘O | missing |
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
| Today tab | Share ▸, Change Icon…, Open in Split View, Archive Tabs Below |
| Pinned tab | Share ▸, Change Icon…, Edit Pinned Page ▸ (submenu), Add Split View, Remove Pin |
| Space header / empty sidebar | Share Space… (*skip*), New Folder, Manage Spaces…, Delete Space (check order) |
| Toolbar address | Share ▸, Capture…, Capture Full Page, Manage Extensions…, Hide Toolbar, Disable Shared Quotes |
| Library button | Show media ▸ Documents, Desktop, Screenshots, Arc Captures, Downloads |

## 4. Settings

| Arc tab | Rows Cra lacks |
|---|---|
| General | Previews Settings…, Block Cookie Banners |
| Profiles | Passwords / Credit Cards / Notifications / Privacy and Security shortcuts to Chromium's pages, "New documents" app |
| Links | "Open Little Arc when clicking on links with ⌥⌘ held", "Archive Little Arcs after" |
| Advanced | Play sound effects, restore windows from previous session, window dragging from the top of webpages, Shared Quotes, websites get theme data, Enable Boosts |
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
