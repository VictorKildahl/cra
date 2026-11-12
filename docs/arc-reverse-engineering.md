# Arc reverse-engineering findings (for Cra)

Target: /Applications/Arc.app, version 1.168.0 (build 88413), bundle id company.thebrowser.Browser, min macOS 13.
Method: REA CLI (rea-agents 6.4.0) `decode-interface-builder`, `inspect-asset-catalog`; `strings` on the arm64 slice;
Arc's own JSON stores in ~/Library/Application Support/Arc; `defaults read company.thebrowser.Browser`.
No Ghidra/IDA/Hopper on this Mac, so no decompiled logic. Nothing below was observed at runtime.

Legend: [O] observed in shipped artifact or data file, [I] inference, [U] unknown.

## Architecture
- [O] Native Swift app. Framework "ARC" with feature modules (CommandBar, SidebarDataStore, StorableSidebar, Archive,
  SpaceStyleEditor, TypeTravel, LittleBrowser, HoverCards...). UI is AppKit: SidebarViewController, SidebarDockViewController,
  NSCollectionView layouts, CommandBarTextField, SuggestionsView.
- [O] Web content is embedded Chromium ("User Data/Default" is a Chrome profile: History, Cookies, Extensions, Preferences).
- [I] So Arc = native chrome + Chromium engine. Cra does the same, with Chromium through CEF.

## Sidebar data model (StorableSidebar.json)
- [O] `sidebar.containers` = [ {global}, {spaces, topAppsContainerIDs, items} ]. Lists are flat [id, object, id, object...].
- [O] SpaceModel: id, title, profile, containerIDs = ["pinned", <id>, "unpinned", <id>], customInfo.iconType {emoji_v2, emoji},
  customInfo.windowTheme = blendedGradient { baseColors[2], overlayColors, modifiers{noiseFactor,intensityFactor,overlay:"grain"},
  wheel: analogous|complimentary, translucencyStyle light|dark } with appearanceBased light/dark variants, plus a
  semanticColorPalette (foregroundPrimary/Secondary/Tertiary, backgroundExtra, maxContrastColor...).
- [O] SidebarItem: id, parentID, title (null unless user renamed; custom title overrides page title), childrenIds[], isUnread,
  createdAt, originatingDevice, data = one of
  - tab { savedURL, savedTitle, savedMuteStatus, timeLastActiveAt, activeTabBeforeCreationID, referrerID?, liveItemID? }
  - list {} = folder (optional customInfo.iconType; optional automaticLiveFolderData for GitHub live folders)
  - itemContainer { containerType: topApps{profile} | spaceItems{spaceID} }
  - [O strings only] easel, splitView, arcDocument, tabGroup also exist.
- [O] Favorites = the "topApps" container, one per profile, shared by all spaces (StorableSidebar.topAppsContainerIDs).
  Cra keeps favorites per space by default; Settings ▸ Tabs ▸ "Share Favorites across Spaces with the same profile"
  (#154) does it Arc's way (see "Favorites per profile").
- [O] Every space owns one pinned container and one unpinned ("Today") container; ordering = childrenIds; folders nest via parentID.
- [O] A pinned tab keeps savedURL/savedTitle as its home; strings: resetTab, resetCurrentTab, replacePinnedTab,
  PinnedTabNavigationProfile, renamePinnedTabsEnabled=1.
- [O] Section chrome: UnpinnedSectionDivider/Header (the line between pinned and Today), SidebarClearButton,
  SidebarTidyButton, SidebarPlusButton (new tab button with menu: newTab/newFolder/newEasel/newNote/newSpace),
  PinnedSectionExpansionState, spacesWithCollapsedPinnedSections.
- [O strings] Pinned-section collapse (Arc 1.170): actions collapsePinnedSection/expandPinnedSection, menu titles
  "Collapse Pinned Tabs"/"Expand Pinned Tabs" (not in the main menu bar, so they live on the space header),
  a separate spaceHeaderContextMenu, analytics event pinnedSectionToggled, onResetVisiblePinnedTabsRequested.
  StorableWindows.json keeps windows[].spacesWithCollapsedPinnedSections (per window). [I] Clicking the space
  name toggles it and the active pinned tab stays visible; not observed live (Arc's window sat on another
  macOS Space and ignored synthetic input, 26 Oct). Cra: WindowPrefs.collapsedPinnedSpaces, SpaceHeader.
  [O 1 Nov] A click on the name does toggle it (see "Space header row" below).

## Window state (StorableWindows.json)
- [O] sidebarWidth 328, sidebarMode "anchored" (binary also has floating, hidden, collapsed), focusedSpaceID, lastFocusedSpaceID,
  expandedItems (folder expansion, per window), itemLastActiveDates, itemCreatedDates, splitViewState, windowContents.

## Spaces
- [O] SidebarDock = space switcher at the bottom (icons/emoji, tooltip), SidebarPagingContainer = horizontal paging between spaces,
  SpaceCreation view, SpaceStyleEditor (color pad, dial, color picker), SpaceIconPicker (emoji), SpaceManagement (reorder),
  focusNextSpace/previous, LinkRouting rules (URL match -> space or Little Arc), per-space profile.

## Archive (StorableArchiveItems.json)
- [O] { archivedAt, reason: manual|auto, source: space{id}|littleArc|standaloneSidebar|unknown, sidebarItem: <copy> }.
- [O] Auto-archive thresholds enum: twelveHours, twentyFourHours, sevenDays, thirtyDays (this Mac: sevenDays, per profile).
- [O] Actions: viewArchive, clearArchive, reopenClosedTab, resetSpace, archiveTab.

## Command bar (ARC_CommandBar.bundle + strings + StorableCommandBarAdditionalRanking.json)
- [O live] ⌘T (9 Nov 2026, Arc 1.172.1 offline copy, 1x sRGB captures + AX, PR #268): panel 766 wide, radius
  ≈12, 1 pt outline, fill ≈ (10,9,9) at ≈0.84 over the blurred page ((51,50,50) over white). Input row 64 pt
  with a 1 pt divider (white ≈0.1); rows 46 tall on a 50 pt pitch, 6 pt under the divider, 10 pt in, radius ≈6,
  bottom padding ≈11. Leading magnifier 12 pt, centred 32 pt in; placeholder "Search or Enter URL…" 18 pt,
  ink (163,162,162); typed text (230,231,233); placeholder and row titles both start 52 pt in. The selected row
  is the space's focus colour ((121,104,33) gold, (70,77,219) default theme; the dark palette on a dark Mac,
  light spaces too), white title and trailing text, a white 24 pt arrow tile with the arrow in the row colour.
  Unselected: titles (214,214,214), "Switch to Tab" / URLs (117,117,117), arrow (189,189,189) on a white-5 % tile
  12 pt from the row's edge. "Switch to Tab" shows before typing. The info badge is a 24 pt circle 21 pt from the
  edge in the space's backgroundExtra and stays while typing. It is a button, not a picture (#314).
  Cra: CommandBarView, CraCore CommandBarTones.
- [O live] The (i) badge (10 Nov 2026, Arc 1.172.1 offline copy, real clicks, 2x captures, #314) is the
  search-suggestions notice (`CommandBar.SearchSuggestionsPrivacyView`), not a Site Control Center button (the
  binary's "placeholder button that opens site control center" is another `CommandBarPlaceholderButtonsView`
  button; it didn't show in ⌘T). Hover does nothing. A click hides the badge and puts a black banner (opaque
  (0,0,0), 60 pt, edge to edge, flush with the bar's bottom) in the last row's place: four rows instead of five,
  same bar height. Inside: a 13 pt (i) circle (ink ≈115) centred 24 pt in; "We talk to your search engine to help
  us suggest results." 13 pt bold (237) from 46.5 pt; "Learn more about your data on Arc here." 12 pt (126), "here"
  underlined (privacy policy); Search Settings… (130.5 × 37 pt, Arc's General pane) and Dismiss (71 × 37 pt), 10 pt
  apart and 10 pt from the edge, corners ≈5, fill (48,47,99) inside a (99,98,174) outline on the default theme
  (focus (70,77,219)), labels (235,235,239). Dismiss writes `commandBarSearchSuggestionsPrivacyHasBeenExplicitlyDismissed`
  = 1 and the badge never comes back. Not seen: whether an undismissed banner reopens with the bar, and the
  badge with search suggestions off. Cra: CraCore SearchSuggestionsNotice, CommandBarView.
- [O] Entry points: keyboardShortcutT, keyboardShortcutL, keyboardShortcutFocusSidebar, keyboardShortcutCommandOptionG,
  sidebarDoubleClick, sidebarNewTabButton, placeholderClick, littleArcPlaceholderClick, topbar, appMenu*,
  toggleBetweenTypeTravelAndCommandBar.
- [O] Result archetypes: tab (switch to open tab; carries customTitle), chromiumHistory, chromiumSearchWhatYouTyped,
  chromiumSearchSuggestion, chromiumNavigateWhatYouTyped, chromiumSearchHistory, chromiumNavigateSuggestion, chromiumBookmark,
  chromiumSearchOtherEngine, chromiumSearchCalculatorAnswer, topDomain (bundled popularDomains.json), typeTravel
  (menuItem:<id>, focusSpace:<id>, moveToFolder:<id>, openFolder<id>, webContentExtension:<name>), askGPTWhatYouTyped,
  siteSearch (scoped pill), staticQuerySuggestions.
- [O] Ranking signals: recentlySwitchedToTabs (last 10 switch times per tab), queriesToSelectedArchetype (typed prefix ->
  what the user picked, i.e. it learns), typeTravelUsage (frequency + last 15 executions), siteEngagementScore,
  fuzzySearchConfidence, hotWords match %, title/url match % and position, recency, importance, customTitlePrefix boost,
  veryRecentTabOrDocumentBoost, derankCurrentItemURL, dedupByTitleAndHostList (figma, notion, github, zoom...).
- [O] Type-travel triggers e.g. "Go to Sidebar Item 3" / "3. tab" / "3. item".
- [U] Weights of the ranking model (a CoreML tensor, CommandBarRankingTensor) are not recoverable statically.
- [O] Site Search (29 Oct, Little Arc driven by keys posted to its pid, 2x captures): Arc seeds 19 sites into
  Chromium's `keywords` table as active (Drive, Gmail, Maps, Calendar, Docs, Dropbox, Amazon, GitHub, Figma, X,
  twitter.com, YouTube, Wikipedia, Reddit, SoundCloud, Asana, LinkedIn, Apple Music, Spotify; URLs in the binary
  next to `rankCommandBar`); Chromium's auto-added engines stay inactive and never offer it. Text that starts an
  active keyword's host shows "Search <name>" (13 pt semibold, white 0.33) and a "Tab" cap (23 pt, white 0.04 fill,
  22 pt from the edge) on the input row: "twit" offers X even while completing twitch.tv, "gm" offers nothing
  (Gmail's keyword is mail.google.com). Tab (not Space: the space trigger flag is off) puts a 73×23 pt round pill
  in the site's colour (hard-coded, e.g. YouTube #FF0000, GitHub #743FC7; glow in the same colour) before the
  field, placeholder "Search…", rows reduced to the typed search tinted with that colour. Backspace on the empty
  field drops the pill and puts back what was typed; Escape returns to how the bar opened. Cra: SiteSearch.all.
- [O] Scopes (1 Nov, Arc 1.171 Swift field names): `ScopedSearchType` has two cases, `siteSearch` and `typeTravel`;
  there is no tab scope. The bar's state keeps `scopedSearchType`, `scopedSearchColor`,
  `queryBeforeEnteringScopedSearch` (what Backspace puts back) and `postScopedSearchRestoration` (Escape); the
  pill is `CommandBarInputScopedSearchPillView`. `migratedToTabOnlySiteSearchTrigger` and
  `siteSearchSpaceTriggerEnabled` show Space was a trigger once and Tab is the only one now. Cra's "%" tab scope
  (#49, Zen's idea) reuses all of it: "%" offers "Search Tabs  Tab", the pill takes the space's colour (Arc has no
  colour for a scope that isn't a site), rows are the bar's own tab rows. Cra: TabSearchScope, CommandBarScope.
- [O] Actions scope (6 Nov, Arc 1.171, ⌘T then Tab posted to the main window, AX + window captures; GitHub #195):
  Tab on the EMPTY field enters `typeTravel` ("title for scoped search of browser actions in Arc"): an "Actions"
  pill in the space's colour before the field, placeholder "Search…", no "Search …  Tab" hint before it. Rows are
  actions only, each with its shortcut (Archive Tab ⌘W, an extension, Close Window ⇧⌘W, Hide Sidebar ⌘S, Next Tab
  ⌥⌘↓: recently used, from typeTravelUsage); typing narrows them ("spl": Add Split View, Add Top/Left/Right/Bottom
  Split) and the glyph before the field becomes the row's. Backspace on the empty field leaves it, Escape returns
  to how the bar opened, a second Escape closes. Neither New Tab nor the command bar itself is listed. Cra:
  ActionSearchScope, CommandBarScope.actions (most used first, then menu order: Cra keeps counts, not times).
- [O] Entering and leaving a scope (3 Nov, Arc 1.171, disassembly of `CommandBar.CommandBarContainer` + a 120 fps
  recording of Little Arc, "youtube" Tab): the container's layer gets `arc_commandBarBounce`, a CASpringAnimation on
  `transform` toward scale 0.95 about the centre (damping ratio 0.9, response 0.7: stiffness ≈ 80.57, damping ≈ 16.16,
  mass 1), its duration cut to 0.1 s, autoreverses, fill forwards: the bar dips ~1% and is back within 0.2 s. With a
  site colour, an `NSHostingController<SplashView>` goes under the bar: `Color(nsColor:)` clipped to a 12 pt continuous
  rounded rectangle, `.blur(radius:)` 0 → 150 and `.opacity` 1 → 0 under `.animation(.easeOut(duration: 1.2))`; on
  screen a haze of the site's colour spreads past the bar over the page and fades. Leaving the scope bounces again and
  drops the splash. Measured side by side (100 fps, same crops, 3 Nov): the bar's edge moves in 0.96% (Arc) / 1.0%
  (Cra) peaking at 80/90 ms on Tab, 1.04/1.07% on Backspace; red 60–140 pt above the bar starts at ~150 ms and peaks at
  10.3 at 450 ms in both, gone by 1 s, within 0.5 at every 50 ms. Arc's splash also shows through the bar: its inside
  goes from (26, 26, 26) to (47, 20, 19) at once, holds for 0.17 s, then fades by 1 s. Cra's material can't see the
  panel under it, so the inside is a layer of the colour under the bar's tint keyed to that curve (within 2 levels).
  Cra: CommandBarView.scopeChanged.
- [O] Search engines (3 Nov): Settings ▸ Profiles has "Default Search Engine" and "Search Settings" (Chromium's page).
  Arc's bar is Chromium's omnibox, so the profile's default (`default_search_provider_data.template_url_data`, kept in
  Secure Preferences with a MAC) and its keywords (Web Data `keywords`) are what it searches with. Chromium adds sites
  it sees as inactive keywords (`safe_for_autoreplace` 1, `is_active` 0); those never take Tab. Cra kept its own engine
  list until 3 Nov (reported on X: custom engines and edited built-in ones did nothing). Cra: ChromiumSearchEngine,
  SearchEngines (reads Web Data as `immutable=1`, Chromium holds it with an exclusive lock), SiteSearch.match.
- [O] Folder glyph (3 Nov, `FolderIcon.FolderIconView` disassembled, checked against AX-toggled folders captured at
  1x): 16 × 16, r = round(W/7), line px(1.25), tab height px(round(H·0.25)), shoulder floor(tab/1.5); back path (r,0) →
  (0.41W,0) → (0.58W,t) → round corners; the front a rounded rect under the tab. Both hinge on the bottom-left
  (anchor (0,1)); per state m34 −0.0029129464, x +3 / Y 32° when expanded (+1.5 / 16° peeked open), then X +28° on the
  back, −30° on the front (half for peeked open). Shading gradients black 0 → 0.36 (back, 0,0 → 0.6,1, opacity 0.2
  closed / 1 open) and 0 → 0.15 (front, 0.1,0 → 0.9,1, 0 / 1). No animation of its own: the state change runs in a
  CATransaction with actions on, so Core Animation's implicit 0.25 s (recorded: 50% at ~95 ms, 90% at ~165 ms in Arc;
  ~105 / ~175 ms in Cra). Colours come from outside (`ColorSpec`): on one
  gold theme the back was #E9B300, the front #FCEDBC and every edge black at ~26%; how the back colour follows the
  theme is worked out in the next entry. Cra: FolderGlyphView. Cra masks the back with the front panel's shape
  (`frontHole`, turned with the front's transform) for the translucent White and Black icon styles.
  The live folder's mark (7 Nov, PR #234, Arc 1.171's ivars and disassembly): `customIconImage` sets
  `_customIconLayer`, which is inserted at index 0 of the front path layer (`insertSublayer:atIndex:0`), so it
  turns with the front panel and sits under the front shading. Arc's other fields there: `frontContainerLayer`,
  `frontPathLayer`, `_frontMaskLayer`, `frontShadingLayer`, `backLayer`, `_backMaskLayer`,
  `backShadingMaskLayer`, `backShadingLayer`, `_badgeLayer`, `_ellipsisLayer`.
- [O] Folder glyph colours (4 Nov, offline Arc 1.171, 2x window captures in sRGB of the default dark theme, a
  dark gold and a light blue, folders opened over AX `AXDisclosing`): every panel is opaque and comes from the
  theme's primaryColorPalette. Back = midTone on every theme. Light themes: front tintedLight (#E4F2F8 exact),
  outline shadedDark (#00607D against #005F7D). Dark themes swap them: front shadedDark (#1F2AFF exact),
  outline tintedLight (#ECEDFF exact). The back reads a little darker under its 0 → 0.36 shade (midTone #8389FF
  shows #797FEF). Cra had a translucent white front on dark themes (white 0.14 over the sidebar; an X report on
  4 Nov said the open folder looked see-through next to light mode) and cream on both light panels.
  Palette fits (`SpaceTheme.midTone` / `tintedLight`, Arc's three palettes within 2/255): midTone = the theme
  colour with its OKLab lightness clamped to 0.68…0.794, at the nearer bound the gamut edge of its HSB hue;
  tintedLight = that colour (floored at 0.68) mixed toward white in sRGB to OKLab 0.95. Cra: FolderTones.
- [O] Sidebar glyphs (29 Oct, 1x and 2x captures, fitted pixel by pixel): the tab row's hover ✕ is two 2 pt
  round-capped strokes 4.25 pt out from a centre on a whole point, white 0.6 over the hover fill; at 1x it is
  perfectly symmetric (176/142/85), which no SF Symbol size reproduces (xmark 13.5 bold is closest at 2x but
  lands between pixels at 1x). Cra strokes it with a CAShapeLayer (SidebarSymbols.closeMark); an NSImage drawn
  the same way rendered thinner and off-centre at 1x. New Tab's plus fits SF plus 14.5 medium at both scales,
  in the label's colour. The New Space plus is a custom square-ended glyph (14 pt, 2 pt stroke).
- [S] ⌘T in a Peek and hover in the bar (12 Nov 2026, Arc 1.172.2's Swift field metadata, `__swift5_fieldmd` of the
  arm64 slice; GitHub #379, #382). A Peek is a `LittleBrowserWindow` with `presentModally` / `modalState`, shown by
  the same `LittleWindowViewController` as Little Arc (`presentedModally`, its own `commandBarInstanceID` and
  `commandBarViewStateInstance`). The bar's `CommandBarDestinationType` is `overrideCurrentTab(showCurrentURL:)`,
  `createNewTab` or `noop`. Which one ⌘T gives in a Peek isn't in the metadata, and no Peek was opened live (it
  needs a click in a pinned tab). Little Arc's ⌘T is ⌘L (Arc 1.168, live, above). Cra (#379, its own until Arc is
  checked): ⌘T in a Peek opens the browser window's New Tab bar, with its tabs; ⌘L edits the Peek; a Little Window
  keeps ⌘T as ⌘L (CraCore `CommandBarOpening`; scenario peek-command-t).
  The row view `CommandBar.CommandBarSuggestionRowView` keeps `isHovered` and a `trackingArea`, and its `Theme` has
  a `hoveredColor` (asset `CommandBarRowHoverBackgroundColor`) beside the selection colour, so hover in Arc's bar
  is its own fill and not the selection. Cra's hover selects the row, and since #382 only after the pointer moves
  from where it was when the rows last changed (CraCore `HoverGate`). Not done: Arc's separate hover fill.

## Key bindings (StorableKeyBindings.json + strings)
- [O] Action = {identifier, name}; binding = {keyEquivalent, deviceIndependentModifierFlags}, priority, typeTravelTriggers;
  user overrides persisted. item1..item9 = "Go to Sidebar Item N" with flags 1048576 (= Command).
- [O] Action identifiers: newTab, newWindow, newBlankWindow, newSpace, newFolder, newEasel, newNote, closeWindow, archiveTab,
  reopenClosedTab, pinTab, rename, duplicate, resetTab, addressBar, typeTravel, toggleSidebar, showSidebar, focusSidebar,
  toggleToolbar, focusNextSpace, nextTab, previousTab, selectNextTab, cycleNextTab, cycleTabForward, goBack, goForward,
  reloadPage, forceReloadPage, stopLoading, findNext, findPrevious, findAndReplace, zoomIn, zoomOut, resetZoom, fullscreen,
  readerMode, copyCurrentURL, viewArchive, clearArchive, viewHistory, viewDownloads, viewLibrary, viewPreferences,
  developerTools, inspectElements, viewSource, printPage, savePageAs, capturePage, captureFullPage, showLittleArc, peekEmail,
  addSplitView, removeSplitView, muteAllTabs, resetSpace, clearCookies, openTabIn, gptMessage, hideArc, hideOthers, minimize,
  quitArc, moveToSpace, moveToTopApps, removeFromTopApps, replacePinnedTab, renameCurrentTab, duplicateCurrentTab.
- [O] Default key equivalents read from the running Arc's menu bar through Accessibility (AXMenuItemCmdChar/
  AXMenuItemCmdModifiers, 24 Oct 2026). File: New Tab ⌘T, New Window ⌘N, Blank Window ⌃⌘N, New Incognito Window ⇧⌘N,
  New Little Arc Window ⌥⌘N, Restore Last Closed Tab ⇧⌘T, Open Command Bar ⌘L, New Easel ⌃⇧E, Close Window ⇧⌘W,
  Close Tab ⌘W, Capture ⇧⌘2, Save Page As ⇧⌘S, Print ⌘P. Edit: Copy URL ⇧⌘C, Copy URL as Markdown ⇧⌥⌘C,
  Copy URL as Quote ⌃⇧⌘C, Paste and Match Style ⇧⌘V, Find ⌘F, Find and Replace ⌥⌘F, Find Next ⌘G, Find Previous ⇧⌘G,
  Jump to Selection ⌘J. View: Hide Sidebar ⌘S, Hide Toolbar ⇧⌘D, Stop Loading ⌘., Refresh ⌘R, Force Refresh ⇧⌘R,
  Add Split View ⌃⇧=, Close Split Pane ⌃⇧-, Zoom Actual ⌘0, Zoom In ⌘+, Zoom Out ⌘-, View Source ⌥⌘U,
  Developer Tools ⌥⌘I, Inspect Elements ⌥⌘C, JavaScript Console ⌥⌘J, Enter Full Screen ⌃⌘F. Spaces: Next ⌥⌘→,
  Previous ⌥⌘←, space N ⌃N. Tabs: Pin/Unpin ⌘D, Next Tab ⌥⌘↓, Previous Tab ⌥⌘↑, Clear Today ⇧⌘K, Go to Tab N ⌘N,
  Toggle recent tabs ⌃Tab. Archive: Go Back ⌘[ (shown as ⌘Æ on a Danish layout) / ⌘←, Go Forward ⌘] / ⌘→,
  View History ⌘Y. Window: Minimize ⌘M, Open Library ⇧⌘L, View Downloads ⇧⌘J.
- [O] File menu, Arc 1.172.1 (AX dump plus window captures, 9 Nov 2026, #279): New Tab…, New Window, Blank Window,
  New Incognito Window, New Little Arc Window, Restore Last Closed Tab | Open Command Bar | New Profile, New Easel |
  Close Window, Close Tab ⌘W (shown only while a tab is selected) | Share…, Capture…, Capture Full Page, Capture in
  Portrait Mode, Save Page As (no ellipsis), Print. AX also lists New Note ⌃⇧N, Archive Tab ⌘W and Send to Dia, which
  never draw (hidden rows). Share… has no default key and opens the standard NSSharingServicePicker (Add to Reading
  List, AirDrop, Mail, Notes | Copy, Edit Extensions…) hanging from the top centre of the page under the toolbar; with
  no tab selected it stays enabled and does nothing. Spaces starts with New Space…; Tabs has New Folder… after
  Open Little Arc or Peek in… ⌘O.

## Visual reference (Arc 1.168, measured at 2x from window captures)
- [O] Sidebar 328pt wide. Row 1: traffic lights, sidebar toggle right after them (~93pt), nav ← → ↻ right-aligned when a
  tab is selected and the toolbar shows the URL; with no tab the nav moves into the toolbar and the toolbar shows a
  centered "Search or Enter URL…". Favorites: 4 tiles, ~44pt tall, active tile gets a dashed outline. Space header: emoji +
  name, 13pt semibold (re-fitted 1 Nov), secondary color. Rows 40pt pitch, 14pt titles, 16pt favicons, a site in developer mode shows its host
  as an 11pt second line (see "A pinned tab away from its page"), folders use a blue folder glyph, nested rows indent 16 pt (measured 3 Nov, #139). Bottom row: library icon
  left, tiny space emoji centered (inactive dimmed), + right.
- [O] Content: rounded card inset ~8-10pt with the toolbar strip (42pt: lock + monospaced URL, copy link, extensions,
  capture, DevTools, sidebar toggle) on top; no card at all when no tab is selected.
- [O] Command bar: ~766pt wide, vertically centered, dark translucent in dark mode. Input row 60pt with the top match's
  favicon; rows 50pt single-line "Title — url"; the completion row comes first, then the typed query, then matches; open
  tabs show "Switch to Tab" + arrow box (other-space tabs show the space name); the selected row is tinted with the
  space color. (Re-measured 9 Nov 2026: input row 64, rows 46 on a 50 pt pitch; see the ⌘T entry.) ⌘L with the toolbar visible edits inline: dropdown hangs under the toolbar across the content width.
  Arc draws the bar inside the window, so it is light or dark with the space's theme; Cra's bar is a child panel,
  which takes macOS' appearance unless given the window's (it was dark over light spaces on a dark Mac until 4 Nov).

## Dia 1.54 (company.thebrowser.dia)
- [O] ~/Library/Application Support/Dia/StorableProfileContainers.json: containers per profile with `window` or
  `favorites` kinds; tabs[].contents[].variant = webContent{_0:{title,url}} | newTabPage. StorableAutoArchive.json:
  containers[].archivedTabs (empty here). Chromium profile at User Data/Profile 7 with Bookmarks whose bookmark-bar
  folders mirror Arc spaces ("Favorites", "Victor", "JYSK").

## Dia 1.55 sidebar store (1 Nov 2026)
- [O] StorableProfileContainers.json stopped being written (last Feb 2026, still names "Profile 1") and the bookmarks
  bar keeps the Arc import from 14 Oct; neither follows the sidebar. Bookmarks also moved to EncryptedBookmarks2
  (OSCrypt v10 of the same JSON, same checksum).
- [O] The sidebar is User Data/<profile>/tabs.db (GRDB with SQLCipher 4 defaults: 4096-byte pages, 80 reserved bytes =
  IV + HMAC-SHA512, raw 32-byte key). Its siblings key_value_store.db, live_data_database.db, assistant.db … are the same.
- [O] Key (BoostBrowser Persistence/DatabaseEncryptionKeyDerivationFunction.swift, read from the arm64 code at
  0x100faf20c and its caller 0x100fc31ec in 1.55.1): `HKDF<SHA256>(ikm: rootKey, salt: HMAC<SHA256>(key:
  base64 "iOe1Ue/XtonbieE/5m1nAgewvWQlePHRcKnoU10EyOM=", label), info: label, 32 bytes)`, label
  `profile/<profile folder>/<name>` ("profile/Profile 7/tabs") or `global/<name>`. rootKey = Chromium's OSCrypt key,
  PBKDF2-SHA1("Dia Safe Storage" secret, "saltysalt", 1003, 16 bytes).
- [O] Tables: `spaces(id, title, creation_date, theme)` with theme a name (neutral, red, orange, yellow, green, blue,
  pink, purple; no icon); `nodes(id, kind, entity_id, parent_id, order, deleted_at, space_id)`, kind tab | group |
  favorites | window | content_pane | pinned_container. Per space one `favorites` and one `pinned_container` node and a
  `window` node per window (open tabs; closed windows have deleted_at). `tabs`, `tab_groups(title, icon JSON, behavior)`,
  `content_panes(custom_title, variant web_content | new_tab_page)`, `web_contents(content_pane_id, url, title)`; a split
  is a tab with several content panes. Dates are GRDB text in UTC. Recent edits often sit only in tabs.db-wal.
  Cra reads it in Services/Import/DiaSidebar.swift.

## Other observed features (not in Cra's first scope)
- Little Arc (LittleBrowser), Peek, Easels, Boosts, split view, hover cards, site control center, sidebar banners,
  sync via CloudKit + Firebase, Chromium extensions, "Tidy", Ask Arc.

## Rendering recipe fitted to Victor's Arc captures (24 Oct 2026)
- [O] Light "Victor" theme (isVibrant, intensity 0.25) renders as #93926A–#AA9470 on this desktop: gradient at 25% over the
  blurred desktop. Cra reproduces it with a behind-window NSVisualEffectView, a 22% white lift and gradient alpha = intensity.
- [O] Dark "JYSK" theme renders #292538 from base #01021F/#1A001F: about 27% of the colour over #2B2632.
- [O] Toolbar strip = first theme colour at 46% (#72601D), URL #E4E0D4 12pt monospaced starting 40pt from the card edge.
- [O] Title row centre 24pt (traffic lights at x 19/43/67, sidebar toggle at 93, nav ← → ↻⌄ at 236/270/299/314).
  Favorites tiles 70×47 with 8pt gaps, first row at y≈45. Space header centre y≈118, rows 41pt pitch, favicon centre x=26,
  text x=45. With no tab selected the content area is a faintly lighter card with a 40pt toolbar strip and a hairline.

## Calibration update, 24 Oct 2026 (afternoon)

Method that finally worked: put a full-screen solid window (white, then black) directly
behind each browser, capture the same screen region, and fit per channel
`out = c + k · backdrop`. `screencapture` output samples as sRGB (a solid #72601D window
reads back as #72601D), so no P3 conversion is needed. Window-id captures (`-l`) show
Arc's sidebar without its backdrop (equal to its inactive look) and include the window
shadow unless `-o` is passed.

Measured on the "Victor" theme (Arc base #F8D558 / #A4F454, overlay → #FF7567, intensity 0.25):

| | over white | over black |
|---|---|---|
| Arc sidebar, top | 206 200 160 | 124 118 77 |
| Arc sidebar, bottom | 212 181 141 | 154 124 82 |
| Cra (final) top | 199 192 152 | 124 117 76 |
| Cra (final) bottom | 213 184 142 | 154 125 82 |

Cra's recipe for light vibrant themes: `NSVisualEffectView` `.hudWindow`, dark appearance,
`state` driven explicitly from app activation (`.active` / `.inactive`; the key-window
heuristic left the blur half flat), no white lift while active, 0.75 lift while inactive.
Gradient top → bottom, stop opacity `intensity·1.8 → intensity·2.33`; stops from the Arc
theme: top = mix(mix(base0, base1, 0.15), white, 0.30), bottom =
mix(mix(base0, overlayEnd ?? base1, 0.30), white, 0.20). Over a dark backdrop Cra is within
2/255 of Arc at every height; over pure white the top is 7–8 darker (the HUD material
passes ~55 % of the backdrop, Arc's blur a little more). Dark vibrant themes keep the
earlier `.underWindowBackground` + 15 % lift calibration.

Toolbar band is opaque and theme-derived (same colour over any backdrop):
light = HSB(h, s + 0.10, v · 0.46) of the raw base colour (#F8D558 → #725F1D; Arc #72601D),
dark = HSB(h, s · 0.6, v · 0.8) (#010220 → #0A0B19; Arc #0E0B16). Pages with a
`theme-color` meta use that colour instead (Kildash #1A1917, Messenger white).

Other measured details: window buttons are muted grey discs (bg −10 %) until the pointer
reaches the sidebar's title row; favicons 16 pt centred 25.75 pt from the window edge; space
header 13 pt semibold (re-fitted 1 Nov; was 14 medium) with no top padding above it; favorites tiles 72 × 47 with 8 pt margins
and gaps; the yellow/black dashed ring (2 pt, systemYellow, 6/6 black dashes) is Arc's
keyboard-focus indicator, shown on a tab chosen without the mouse, never on clicked ones.
Re-measured 29 Oct (issue #12, ScreenCaptureKit frames every ~60 ms): an AppleScript select
of a tab in another space switched the space and drew the ring ~0.4 s later, still there
2.5 s on; a select within the shown space drew none. Cra rings only a tab switcher pick
that changed space; next/previous tab and ⌘1–9 stay in the space and show no ring. Host subtitles: wrongly read
here as "a pinned tab that left its host"; Arc's code (3 Nov, #139) shows the host only for a site in
developer mode, and ahrefs.com is in Victor's StorableDeveloperModeState.json.

### DevTools docking (CEF 154 note)

`ShowDevTools` with a `SetAsChild` window info (which forces Alloy style on macOS) hits a
CHECK inside CEF 154 regardless of the parent view (tested with the real host and with a
hidden temp window). An Alloy-style top-level DevTools window works, so Cra creates that
hidden (`windowInfo.hidden`), then attaches CEF's window as a borderless child window over
the dock area and keeps its frame in sync from `ShellView.layoutContentChildren`. Moving the
DevTools NSView into Cra's window would be unsafe: CEF closes `view.window` when DevTools
closes.

### Measuring while the Mac is in use (lessons)

A TCC prompt left behind by a Cra instance launched from the agent's shell blocked every
GUI helper spawned from that shell (they never reached `applicationDidFinishLaunching`),
which silently invalidated three colour runs; `killall UserNotificationCenter` cleared it.
Run the app from outside ~/Documents (`CRA_INSTALL_DIR=<dir> scripts/build.sh` copies it there) so no prompt appears.
Animations were verified with `screencapture -V` recordings and a per-frame difference
tool: space switch 11 consecutive 60 Hz frames, sidebar hide 10 frames with a fast start
and soft landing, command bar fade-in 7 frames; the 80 ms fade-out still lands in one frame.

### DevTools dock, final shape (24 Oct, evening)

Arc shows Chrome's docked DevTools (close button, device toggle, rounded card corner).
In CEF 154 the docked frontend (`can_dock=true`) reserves a 150 px "inspected page"
placeholder inside its own window and, after a second navigation, loses its target
connection (empty Elements panel, blue toolbar). Cra therefore keeps the undocked frontend
(fills the pane, stays connected) and injects a plain HTML close button after the ⋮ menu in
the main toolbar; that button and `InspectorFrontendHost.closeWindow()` reach the shell as a
console message, which calls `CloseDevTools()`. The CEF window is non-opaque with its right
corners masked to the card radius. Still missing versus Arc: the device-mode toggle, which
the frontend only offers when it can dock.

### Developer Mode, shortcuts, extensions (24 Oct, evening)

Arc's View ▸ Developer submenu (read via Accessibility): View Source ⌥⌘U, Developer Tools
⌥⌘I, Inspect Elements ⌥⌘C, JavaScript Console ⌥⌘J, "Turn off Developer Mode for this
site" ⌃D. ⇧⌘D is Hide Toolbar and ⌘D is Pin/Unpin Tab. Developer Mode is per site and
swaps the toolbar: default = nav buttons left, centred host (path dim with Show Full URL)
behind a link glyph, sidebar toggle right; developer = lock + full monospace URL left,
copy/capture/DevTools/source icons right, nav buttons in the sidebar's title row. Cra
stores the hosts in `AppSettings.developerHosts`.

Local servers are in Developer Mode before anyone turns it on (8 Nov 2026, #228). Arc's
StorableDeveloperModeState.json holds `enabledHosts` and `disabledDefaultHosts`, and Victor's
has `"disabledDefaultHosts": ["localhost"]` after ⌃D turned it off there. Checked live in
Victor's hidden Arc 1.172 (AppleScript new tab, then the AX tree; a sidebar row's
`sidebarItemSubtitleTextField` shows host:port only in Developer Mode, e.g. ahrefs.com and
example.com from `enabledHosts`): `127.0.0.1:47188` and `app.localhost:47188` showed it,
`[::1]:47188` didn't, and localhost didn't because Victor had turned it off. The
`(localhost|127\.0\.0\.1)` regex in ARCFoundationBase's String+URL is URL detection, not this.
Cra: `AppSettings.isDefaultDeveloperHost` and `disabledDefaultDeveloperHosts`; scenario runs
start with 127.0.0.1 turned off so ${PAGE} keeps the normal bar.

The ⌄ after ↻ in that title row (GitHub #89, Arc screenshot from vrubzov1957): "✓ Reload ⌘R",
"Refresh (Ignore Cache) ⇧⌘R", a separator, "Clear Cookies and Refresh". Arc's context menus show
the shortcut glyphs of rows that have one. Cra's chevron lists Refresh ✓ ⌘R, Force Refresh ⇧⌘R |
Clear Cookies, Clear Cache | View Source ⌥⌘U, Developer Tools ⌥⌘I in the menu bar's words, and
every context-menu row for a KeyBindings command shows its keys, overrides included
(`MenuItems.add(_:action:)`, `NSMenuItem.showShortcut(of:)`). The split row's per-pane submenus don't:
each pane has one and the keys act on the focused pane.

Extensions: CEF 154 has no extension API for Alloy-style browsers. A spike
(`cra://debug?chromeSpike=<url>`) proved the alternative: a Chrome-style Views window
(`CefWindow` + `CefBrowserView`, `GetChromeToolbarType = CEF_CTT_NONE`, frameless, runtime
style CHROME) attached as a child window over the content area loads unpacked extensions
from `~/Library/Application Support/Cra/Extensions/*` via `--load-extension` (an MV3
content script rendered its banner). Chrome style also docks DevTools natively. Moving the
page browsers to that hosting is the route to extensions; one Chrome-style window per tab.

## Split View (Arc 1.170.0, 24 Oct 2026, evening)

Method: REA CLI 6.4.0 `inspect-macho` (Evidence ev_84b238…, arm64 SHA-256 25af5f4e…) and `demangle-swift`
(ev_026c6350…); REA's `inspect-native-dispatch-metadata` refuses the 80 MB executable (64 MiB budget). The
model below comes from parsing the arm64 slice's Swift reflection metadata (`__swift5_types` /
`__swift5_fieldmd` / `__swift5_proto`, nominal types with their stored properties and enum cases) and
`otool -oV` Objective-C class data (selectors, ivars), plus the user's own
~/Library/Application Support/Arc/StorableSidebar.json (21 split items) and StorableWindows.json.
No decompiler, so property names and types are observed; the algorithms are inferred from them.

### Where it lives
- [O] Everything is in Arc's native Swift shell, not in Chromium. ArcCore (Chromium) only carries upstream
  Chrome's own `tabs.createSplit` / `splitViewId` extension API and "Cannot create split view with
  non-adjacent tabs" strings; the Arc UI never references them.
- [O] Generic engine: `ARCUI.SplitViewController: NSViewController` (module ARCUI, file
  ARCUI/SplitViewController.swift) with `SplitViewControllerLayout` (pure layout types) and
  `SplitViewContentPaneView`. It is NOT built on NSSplitView: no Arc class implements any
  `splitView:…` delegate selector (the NSSplitViewDelegate selectors in the binary are protocol metadata
  only). The one NSSplitView subclass, `WebContentViewControllerSplitView` (private to
  WindowContentViewController, overrides mouseDown/mouseUp/viewDidEndLiveResize, `onDidEndLiveResize`),
  is a per-pane inner split, not the pane layout. [I]
- [O] Arc-specific glue: `Arc.WindowContentsContainerViewController: XiblessViewController<NSView>`
  conforms to `SplitViewControllerDelegate`, owns one lazy `splitViewController`, a
  `LayoutConstraintsMap<SplitViewConstraintType>` (leading, trailing, top, bottom, minHeight) and a lazy
  `splitViewTopConstraint`. Each pane is an `Arc.WindowContentViewController` (conforms to
  `SplitViewContentPaneWithInsets`); an empty/drop pane is `SplitViewContentPlaceholderView` (NSView with
  `contentInsets`, a `BorderView` with `borderColor`, also `SplitViewContentPaneWithInsets`).
- [O] State is TCA (ComposableArchitecture): `Store<WindowState, WindowAction>` with view stores; feature
  modules WindowContents (`SplitViewState`, `SplitViewLayoutCache`, `WindowSplitViewLayout`,
  `WindowContentPresentationDisposition`), SharedWindowFeature (`WindowAction.SplitViewAction`),
  BaseModels (`SidebarSplitViewData`, `SplitViewPaneMenuOperation`), SidebarUI (`SplitViewCellState`).

### Data model
- [O] Sidebar: a split is a sidebar item like a folder. `SidebarItemData.splitView(SidebarSplitViewData)`
  with `itemWidthFactors: [Identifier<SidebarItem>: CGFloat]`, `layoutOrientation: horizontal|vertical`,
  `timeLastActiveAt: Date?`, `customInfo: { iconType: SidebarCustomIcon }?` (user icon, used together with
  the item `title` when renamed), `focusItemID: Identifier<SidebarItem>?`. The tabs are the item's
  `childrenIds` (order = pane order, left→right / top→bottom). JSON on this Mac:
  `{"data":{"splitView":{"itemWidthFactors":[<id>,0.3835,<id>,0.6165],"layoutOrientation":"horizontal",
  "focusItemID":<id>,"timeLastActiveAt":…,"customInfo":null}},"childrenIds":[…],"parentID":<container>,…}`.
  All 21 local splits: 2 children, horizontal, parent = a space's pinned/unpinned container (not inside
  folders here), title/customInfo never set. Untouched splits store a single factor `[firstChild, 0.5]`;
  after a drag both factors are stored and sum to 1.0. One zombie split with 0 children exists; the
  binary logs "Noticed zombie split view (without any children)" (`ZombieSplitSeenLocation`:
  rawUpdate/appliedChange/publishedValue) and repairs it on sync. [I] Missing factors = equal share of
  the remainder.
- [O] Window: `WindowContents.State { windowContents: [WindowContentID: WindowContent], splitViewState,
  modalWindowContentV2State, windowContentSidebarItemMap: BidirectionalMap<WindowContentID,
  Identifier<SidebarItem>> }`. `SplitViewState { windowContentIDs: OrderedSet<WindowContentID>,
  layoutOrientation, interactionState, focusedContentID }`; only `windowContentIDs` + `focusedContentID`
  are Codable (StorableWindows.json `splitViewState`), orientation and widths are rebuilt from the
  sidebar item. `InteractionState { activePaneEditStyles: Set<.dragAndDrop>, proposedWindowContentDropTarget:
  WindowContentID?, isResizingPanes }`. Legacy `SplitViewState_Legacy { windowContentIDs }`.
- [O] Per-window width cache: `WindowSplitViewLayout { paneWidths: [CGFloat] }` kept by
  `SplitViewLayoutCache { storeLayoutForWindowID, layoutForWindowID }` (a TCA DependencyKey) and
  handed to the view as `restorableSplitViewLayout`; `SplitViewWindowContentContext { numPanes,
  restorablePaneWidths: [CGFloat]?, splitViewLayoutOrientation }` is what the container passes to
  `SplitViewController`.
- [O] Container view state (`WindowContentsContainerViewController.ViewState`): `splitViewWindowContentIDs:
  OrderedSet<WindowContentID>`, `focusedContentID`, `splitViewLayoutOrientation`, `restorableSplitViewLayout`,
  `canDragOntoSplit`, `isDraggingToCreateSplitView`, `shouldShowInteractivePaneInsertionHandle`,
  `contentInsets`, `contentCornerRadius`, `hiddenScrimEdges`, `sidebarPresentation`.

### The layout engine (ARCUI.SplitViewController)
- [O] Properties: `draggerHandleWidth`, `draggerHandleHitTargetOutset`, `minimumPaneWidth`,
  `layoutOrientation`, `displayInteractivePaneInsertionDraggerHandle`, `allowInteractivePaneInsertion`,
  `verticalLayoutOrientationFromDragAllowed`, `shouldDisplayDraggerPaneForSecondaryAxis`,
  `isDragDropHapticFeedbackEnabled`, weak `delegate`, `contentPanes: OrderedDictionary<Identifier<ContentPane>,
  ContentPane>`, `paneResizeState?`, `dragDestinationState?`, `dragSourceState?`,
  `dragInfoSubject: PassthroughSubject<NSDraggingInfo, Never>`, lazy `minimumWidthConstraint`.
- [O] `SplitViewControllerLayout.ContentPane { id, view: NSView & SplitViewContentPane, trailingDraggerHandle,
  bottomDraggerHandle: DraggerHandle { view: NSView & SplitViewControllerDraggerHandleType }, widthFactor: CGFloat,
  resizeStyle: flexible|fixed, displayState: collapsed|expanded, inFlightTransition: StateTransition?,
  content: .dropRegion(NSView) | .viewController(SplitViewContentPaneContentViewController) }`.
  `StateTransition { identifier: UUID, targetState, style: .animated(removePaneOnCompletion: Bool) | .immediate,
  draggerHandleWidth: CGFloat? }`. `ContentPanePair { leading, trailing? }`.
- [O] `SplitViewControllerLayout.Context { contentPanes, containerSize, backingScaleFactor, minimumPaneWidth,
  draggerHandleWidth, displayInteractivePaneInsertionDraggerHandle, shouldDisplayDraggerPaneForSecondaryAxis,
  layoutOrientation, yAxisOriginAtTop }` → frames are a pure function of the context (pixel-snapped via
  backingScaleFactor). [I] Each pane gets `widthFactor × (container − handles)` along the main axis, clamped to
  `minimumPaneWidth`; every pane carries its own trailing (horizontal) and bottom (vertical) handle view, the
  last one hidden or used as the "insert a pane here" handle when `displayInteractivePaneInsertionDraggerHandle`.
- [O] Resize: `PaneResizeState { initialClickLocationInDragHandle: CGPoint, canSnapToCenter, isCenterSnapped }`
  driven by `handleDraggerPanGesture:` (NSPanGestureRecognizer) and `handleDraggerDoubleClickGesture:`
  (double-click a handle = reset to equal widths, [I]). Dragging snaps to the 50/50 centre when allowed.
  Pane add/remove animates via `StateTransition` (collapsed ↔ expanded, remove on completion).
- [O] Panes are hosted in `SplitViewContentPaneView: NSView { contentView, contentConstraints:
  LayoutConstraintsMap<NSLayoutConstraint.Attribute>, lockContentWidth: Bool, lockedContentAlignment:
  leading|center|trailing, userInteractionEnabled }` (overrides hitTest). [I] While a handle is being
  dragged the web content keeps its old width and is pinned to one edge instead of relayouting Chromium on
  every mouse move; `userInteractionEnabled=false` blocks the page from eating the drag.
  `WindowContentViewController` adds `ContentResizeMode { intrinsic, throttle, locked }`,
  `pendingResizeFrames`, `resizeTimer`, `lockedContentSize`, `contentResizeThrottleSubscription`; the
  container has `isAnimatingResize` and `ContentSizeThrottleFlags` (OptionSet).
- [O] Handles: Arc's `SplitViewDraggerHandleView: FlippedView` (vertical divider: lazy `handle` NSView pill,
  `backgroundView: WindowBackgroundContainerView?` so the space theme shows through the gap, `isHighlighted`,
  `draggableArea: NSTrackingArea`, `draggableRegion: CGRect`, `resetCursorRects`, mouseEntered/Exited,
  `contentAppearance`) with `ViewState { displayBackgroundView, windowBackgroundConfiguration,
  contentOverBackgroundAppearance, isHandleVisible, metalWindowBackgroundRenderingEnabled }`;
  `SplitViewBottomDraggerHandleView` for vertical layouts adds `handle: .dragger | .scrimLoader` and
  `isContentBelowLoading` (the handle doubles as a loading scrim). ARCUI ships a plain
  `SplitViewControllerDefaultDraggerHandleView`.

### Drag and drop (how a split is created with the mouse)
- [O] `SplitViewController` is both `NSDraggingSource` and `NSDraggingDestination` (draggingEntered/Updated/
  Exited/Ended, prepareForDragOperation, performDragOperation, wantsPeriodicDraggingUpdates,
  updateDraggingItemsForDrag, draggingSession:…). `DragSourceState { contentPaneID, initialIndex,
  initialWidthFactor, contentPaneSnapshot: NSImage?, contentPaneSize }` = reordering a pane by dragging its
  toolbar (snapshot image as drag preview). `DragDestinationState { operation: NSDragOperation,
  isDraggingInView, proposedTarget: DropTarget?, isDraggingContentPane }`.
- [O] `DropTarget = .replaceContent(index) | .insertContent(index)`; `ProposedDropTargetInfo { target,
  dropRegionInsertionIndex: Int?, existingDropRegion: ContentPane?, layoutOrientation }`. [I] Hovering near an
  edge inserts a temporary `.dropRegion` pane (placeholder view, animated open) at that index; hovering over
  the middle of a pane proposes replacing it; `verticalLayoutOrientationFromDragAllowed` lets a drop on the
  top/bottom edge flip the layout to vertical.
- [O] What can be dropped (`WindowContentsContainerViewController.SplitViewDragItem`): `.sidebarItem(id)`
  or `.url(URL)`. Actions: `onDropSidebarItem(itemID, target, layoutOrientation, maybeMoveDecision)`,
  `onDropURL(url, target, layoutOrientation)`, `onDidUpdateSplitViewProposedDropTarget(WindowContentID?)`,
  `onDidBegin/EndSplitViewInteractivePaneEditingWith(.dragAndDrop)`.
- [O] Sidebar side: dragging a tab over another tab's left/right half (`SidebarDropTargetRegion = left|right`,
  `TabSplitViewPosition = left|right`) shows `SplitDragPreviewView` (title, favicon, "tab info" and "empty"
  background containers) after `splitDropTargetDelaySatisfied`; dropping makes a split item. Flags:
  `drag-to-combine-tabs-into-split-enabled`, `sidebar-drag-to-split-preview-ui-enabled`, `win-drag-to-split-enabled`.
  Onboarding copy: "Drag a tab from your sidebar into the middle of the screen to create a Split View."

### Commands, menus, entry points
- [O] `WindowAction.SplitViewAction`: `addPanel(index: InsertionLocation, showCommandBar: Bool)`,
  `movePanel(from:to:)`, `onDropSidebarItem`, `onDropURL`, `onDidBeginWindowContentsSplitViewPaneResize`,
  `onDidEndWindowContentsSplitViewPaneResize(WindowSplitViewLayout)`, `onDidUpdateSplitViewProposedDropTarget`,
  `onPaneCreated(source)`, `onPaneClosed`, `onDidRestoreSplitViewState`, `containerDelegate(…)`,
  `panelAction(ContentToolbarAction)`. Container delegate: `onDidAddItemsToContainer`,
  `onDidMoveItemsWithinContainer`, `onDidRemoveItemsFromContainers(itemIDs)`, `onDidAdjustLayoutOrientation`.
- [O] Where a new pane goes: `WindowContentPresentationDisposition.splitView(SplitViewTarget)` with
  `.paneAtIndex(Int) | .newPane(InsertionLocation) | .pane(WindowContentID) | .replaceAllPanes |
  .firstEmptyOrNewPane`; `InsertionLocation = .index(Int) | .after(id) | .before(id) | .last | .afterFocusedPane`.
- [O] Pane menu (`SplitViewPaneMenuOperation`, each `.enabled|.disabled`): moveLeft, moveRight, addPaneLeft,
  addPaneRight, addPaneTop, addPaneBottom, separate, copyLink, flipLayoutOrientation. Toolbar menu items
  (`ContentPanelSplitViewMenuItemType`): move/add/separate/copyLink × horizontal/vertical, flipToVertical,
  flipToHorizontal. Sidebar context menu on a split: `childItem(id, .separateFromSplitView)`, `separateAllItems`,
  `addPanel`, `flipLayoutOrientation`. Toolbar hover actions: separate, close, addHorizontal, addVertical,
  move, copyLink (`split-view-actions-hover-button-enabled`).
- [O] Menu strings: "Add Vertical Split View", "New Bottom Split", "Add Bottom Split", "Convert to
  Horizontal/Vertical Split View", "Flip to horizontal/vertical split view", "Close Split View Pane", "Separate Tab
  from Split", "Remove Tab from Split View", "Open in Split View", "Add to Split View", "Share Split View",
  "Multitask with Split View", "Switch to next/previous Split View", "Jumps to the first…fourth Split View page".
  Type-travel candidates: AddLeft/Right/Top/BottomSplit, ConvertToHorizontal/VerticalSplitView,
  NewVerticalSplitViewPane. Key bindings (see above): Add Split View ⌃⇧=, Close Split Pane ⌃⇧−.
- [O] Entry sources tracked (`SplitViewEnteredSource`): plusButton, windowContent, dragAndDrop, menu,
  contextMenu, alternateClick (option-click a tab), typeTravel, tabCreation, easel, navigationBar, tabHoverMenu.
  Option-click on a split child's close button un-splits (`option-click-split-tab-close-button-to-unsplit-enabled`).
- [O] Limits: errors `splitViewMaximumPanesExceeded`, `splitViewTargetOutOfRange`,
  `unableToInsertSplitViewContainer`, `missingSplitViewContainer`; `ModalParentSplitState { parentIsSplitCompatible,
  numberOfPanels, maximumNumberOfPanels, layoutOrientation }`. [I] Max is 4 panes (shortcuts stop at "fourth").
  Toolbar `shouldShowSplitViewClose` only in a split; `maximizeCurrentSplitViewPane:` exists (notification token).

### Sidebar cell
- [O] `SplitViewCellView: SelectableCellView<SplitViewCellState>` with `SplitViewCellState { sidebarItemID,
  isCurrentItem, isContentVisible, isKeyDraggedItem, isHighlighted, isMultiSelected, shouldDim, canResetTab,
  layoutStyle: .childItems(OrderedDictionary<id, ChildItemState>) | .customInfo(CustomInfo), colorPalette,
  closeItemShortcut, lastUpdatedLocally, hasLeadingRecordingIndicator, dropTargetRegion?, closeButtonConfiguration,
  closeButtonAction, shouldPerformUserAttentionAnimation }`. `ChildItemState { itemID, iconType: FaviconType?,
  title, isGroupSelected, isRecording, closeButtonConfiguration, optionClickSplitTabCloseButtonToUnsplitEnabled,
  newSplitSeparationMechanismsEnabled }`. `CustomInfo { title, isEditingTitle, icon: .childItemCount(Int) |
  .customIcon(SidebarCustomIcon) }`.
- [O] Views: `SplitViewCellChildrenContainerView` (one `SplitViewCellChildItemView` per tab, `separatorLayers:
  [CALayer]` between them, `isGroupHovered`, `InsetSpec { defaultInset, extendedInset }`), each child with
  favicon + title + its own close button and recording dot; renamed splits show `SplitViewCellCustomInfoView`
  (icon or item-count badge `SplitViewCellItemCountIconView`, editable title, hover subtitle). Icons:
  icon-split-add-left/right/top/bottom, icon-split-horizontal/vertical, icon-split-move-*, icon-separate-from-split,
  icon-split-share-*, icon-split-x; colour asset SplitViewLeftBackground.

### Plan for Cra (design, not observation)
1. Model: add `ItemData.split(SplitData)` to SidebarModel with `widthFactors: [UUID: Double]`,
   `orientation`, `focusTabID`; children = the pane tabs (reuse `childrenIds`/`parentID` like folders). Store
   per-window `splitState { paneTabIDs, focusedTabID }` in WindowPrefs; rebuild widths from the item.
2. Engine: a `SplitPaneLayout` value type (panes with widthFactor, min width, handle width, orientation,
   pixel snap) → frames; a `SplitContainerView` in ShellView's `webContainer` that owns one pane view and one
   handle view per visible tab. Cra's CEF browsers are child windows positioned by
   `MainWindowController.positionPageWindows`, so each pane needs its own screen rect: change
   `BrowserManager.show` to a set of visible tabs and `onWebFrame` to deliver per-tab rects.
3. Resize: pan on the handle updates factors; during the drag freeze each page window's size (Cra already
   has `frozenWebBounds`) and only move it, resize once on mouse-up (Arc's lockContentWidth/throttle);
   double-click = equal widths; snap at 50/50.
4. Creation: ⌃⇧= adds an empty pane (placeholder with dashed border + command bar); drag a sidebar tab onto
   the content card: edges insert, centre replaces; option-click a tab adds it as a pane; context menu
   "Open in Split View"; "Separate", "Flip orientation", "Close pane".
5. Sidebar: a grouped row showing each pane's favicon+title with hairline separators, group selection
   highlight, per-child close, rename → icon/count badge.

### Chrome-style page hosting (24 Oct, night)

Pages are now Chrome-style CEF browsers (`CefBrowserView` in a frameless `CefWindow`,
`GetChromeToolbarType = CEF_CTT_NONE`), one window per loaded tab, attached as child
windows over the content card and positioned from `ShellView.onWebFrame` (animated with the
sidebar through `onAnimateWebFrame`). The status bubble, toasts and find bar moved into a
transparent overlay panel above the page windows. This is what makes Chrome extensions work:
folders under `~/Library/Application Support/Cra/Extensions` are passed with
`--load-extension` at start-up (verified with an MV3 content script on a real tab). Popups
come through `GetDelegateForPopupBrowserView`/`OnPopupBrowserViewCreated` and are hosted
the same way; Chrome's DevTools popup is caught with `OnBeforeDevToolsPopup` and docked by
the shell like before. Chrome's session restore had to be switched off
(`--no-startup-window`, crash-restore bubbles hidden) because it resurrected a killed
session's window as a framed Chrome window. The old embedded (Alloy) hosting stays behind
Settings → "Chrome engine for pages" for comparison; it has no extension support in CEF 154.

### Animation timing, Arc vs Cra (measured 24 Oct, VFR screen recordings)

Space switch: Arc ≈ 0.17 s of visible motion (4 distinct frames), Cra ≈ 0.18 s (11 frames
at 60 Hz, `.snappy(0.24)`). Sidebar hide: Arc changes the sidebar strip in 2 frames
(≈33 ms) and settles over ≈150 ms; Cra now runs a 0.14 s ease-out (≈4 frames of motion plus
a short settle), down from 0.22 s. Command bar: Cra fades in over 7 frames; Arc's bar also
appears in a single frame.

### Final state (24 Oct, late)

With a 3 % lift the sidebar sits within ±6/255 of Arc at every sampled height over both
white and black backdrops (top over white: Cra 201 194 154 vs Arc 206 200 160; top over
black: 128 121 80 vs 124 118 77). Sidebar hide now completes in 2–3 frames like Arc's
(0.08 s ease-out); the command bar appears and disappears in a single frame, like Arc's. What cannot be matched
from Cra's side: Arc's signed-in favorites and page state, its "Ahrefs / ahrefs.com"
subtitle (no visible rule), and the DevTools device-mode toggle (Chrome only offers it when
it docks the frontend itself, which CEF does not allow for these windows).

## Chrome metrics re-measured (Arc 1.170.0, 24 Oct 2026, evening, window-id captures)

Measured with `screencapture -l<id>` of Arc's main window against Cra's shell window at the
same 1728×1084 frame, probing pixel runs at 2x:
- Content card: 10 pt inset (card top at y=20 px), corner fits a circular 12 px radius
  → `contentCornerRadius` 6 pt (was 10). The card starts at the sidebar's right edge with
  no gap; Victor's Arc sidebar was 284 pt wide in this capture.
- Toolbar strip (default mode, Messenger, theme-color white): 32 pt tall (y 20–83 px),
  1 px hairline #F2F2F2 under it at 42 pt from the window top. The earlier "40/42 pt" figure
  included the card inset. Nav glyph centres 21 / 58 / 94 pt from the card's left edge.
- Favorites tiles: 47 pt tall, 8 pt gaps, corners fit a circular 26 px radius (13 pt).
  Inactive tile = sidebar colour × 0.955 (black ≈ 4.5 %); active tile = white ≈ 38 % over
  the sidebar (same as the hover fill) with a 2 pt rim of black ≈ 17 % inside the edge.
  No dashed ring on a clicked tab (the yellow/black ring stays keyboard-only).
- Sidebar glyphs (sidebar toggle, library, +) render at ≈ 26 % black over the sidebar
  (toggle 179/173/144 over 229/221/184); Cra had them at 58 %. Arc's library icon is a
  filled box with a confetti puff above it; Cra uses `archivebox.fill` (no puff).
- Not verified here: hover fills and animation timings. Window-id captures cannot show
  hover states, and the Mac was in use (Dia full screen in front), so no pointer was moved.

### Little Arc (24 Oct, night) → Cra's Little Windows

Observed live in Arc 1.168 (`open -a Arc <url>` with Arc in the background opens a Little
Arc; window captured with `screencapture -l`, hover states by moving the pointer with
`cliclick m:`, the open animation with `screencapture -V` at 60 fps, colours probed per
pixel). StorableWindows.json records each one as `little { profile: {default: true},
session: { entryPoint: { externalLink } }, preferredFrame }`; closed ones land in the
archive with source `littleArc`; `LittleBrowserWindow_size` keeps the last size.

Window 1688×1010 (Victor's size), corners 10pt. One 46pt strip, no sidebar, page edge to
edge below it. Colours are the default profile's dark palette even with the light "Victor"
space focused (bar #0C091C = JYSK's toolbar colour, so the strip is theme-derived but not
from the focused space; Cra uses the measured values as a fixed palette):
- traffic lights at x 17/39/61, 12pt muted grey discs (#565660) that colour only while the
  pointer is over them;
- search pill x 83 → 10pt before the button, y 8…38 (30pt, radius 8), fill #252234, hover
  #2D2E3E; magnifier 13pt at x 100; URL host 13pt #A3A1A9 centred; puzzle (extensions)
  and link (copy URL) icons 16pt #6E6F80 centred 46pt / 15pt from the pill's right edge, hover
  = 26pt rounded square #413946 with a brighter glyph;
- "Open in **Victor** ⌘O | ⌄" button, 7pt from the right edge, 30pt tall, radius 7, fill
  #050625 with a 1px #1D1E37 border; "Open in" 13pt medium #828392, the space name 13pt
  bold in the target theme's light foreground (Victor → #FCEDBC), ⌘O badge 33×16 radius 4
  #171832 / text 11pt #8B8C99; 1px divider, 29pt chevron part; each half lightens to
  #161734 on hover;
- clicking the pill (or ⌘L / ⌘T) opens Arc's command bar inside the window, 500pt wide,
  its top a third of the way down, URL prefilled and selected;
- the chevron opens LittleBrowserMoveMenu: a 240pt navy popover (#050625, 1px #1D1E37
  border, radius 12) hanging from the window's top-right corner: "Search Spaces…" row with a
  28pt chevron-up button (#5C5C71), then 54pt rows (40pt radius-9 tile in the space colour
  with the emoji, 15pt semibold name), highlighted row #161734; typing filters, ↩ moves the
  tab there;
- [O] Arc 1.172.1 changed the menu (10 Nov, GitHub #331; offline copy with 10 spaces and with 1, AX
  frames and 2x window captures). It is drawn in a transparent window the size of the Little Arc, so
  no window animation. 244 pt wide with a hairline #1D1E37 border, 4 pt below the window's top and
  4 pt in from its right edge. Header 46 pt: 14 pt magnifier 16 pt in, "Search Spaces..." (three periods, added in code) 13 pt
  #8E8F9D from 46 pt in, an 18 pt #1D1E37 rule 38 pt from the right edge, then a plain ∧ (16 pt
  button, glyph centred 22 pt from the right); glyphs #505166. No filled button any more. Rows
  46 pt: 26 pt tile 10 pt in, centred; name 13 pt semibold at 46 pt, white ≈ 82 %; highlight
  #161734 across the full width. The list (an AXScrollArea) is at most 350 pt and scrolls. The
  space "Open in" names is the first row and highlighted, the rest follow in sidebar order (Work,
  Victor, Alpha… with sidebar order Victor, Work, Alpha…). ↓ moves the highlight but doesn't
  scroll the list to it (Cra does). Typing shrinks the menu to the matches ("al" → 46 + 46 pt);
  with none, "No results" 13 pt centred in 64 pt. ⇧⌘O opens the same menu. With one space the
  real ⌄ (the second `openInSpaceExpander`) isn't there: the button is "Open in Work ⌘O" alone.
  Cra: `LittleMoveMenu` (CraCore) and `LittleSpacesPopup`.
- ⌘O ("Open in <space>") moves the page into that space; ⌥⌘N makes an empty Little Arc;
  Window ▸ Close Little Arc Windows exists;
- opening: the window grows from a small rectangle under the pointer to its full frame in
  ~120 ms (6–7 frames), content laid out at full size, no fade.

Second pass (25 Oct, morning), hover details: the traffic lights are #686871 discs while the
window is key and the pointer is elsewhere; the puzzle, link and chevron controls show Arc's
own tooltip after ~0.4 s, a 28pt pill (#0A0D4B, 1px #22255D border, radius 10) hugging the
strip's bottom edge, 14pt semibold #DEDFFD text, shortcut key caps 20pt (#D3D4FD, glyphs
#282EFC): "Extensions", "Copy URL ⇧ ⌘ C", "More Spaces" (the latter right-aligned to the
window edge). The "Open in" halves have no tooltip. Cra reproduces all of it in
LittleWindowController (LittleTooltip); hover is tracked by AppKit with an activeAlways
tracking area because SwiftUI's onHover sleeps while the Chrome page window is the key
window.

Arc 1.172.1 (build 90370), re-measured on 10 Nov 2026 from 2x window captures
(`screencapture -l`, colours read from the PNGs' pixels) by kKr1Xx (GitHub #329, #330, PR #334):
- the strip is a gradient, not #0C091C: #242438 at the left end of a 1185 pt window, #26243A,
  #292839 and #2C2439 between, #312339 at the right end, identical after switching spaces. The
  pill is a lighter wash over it (about #38394A on the left, #43394B on the right, white at
  9–10 %). The traffic lights are grey discs (about #6A6A74) until the pointer is over the
  group, with the window in front;
- the pill reads the host only (`cra-measure.lvh.me` for `http://cra-measure.lvh.me:47110/page?e=link1`),
  and for a page that isn't served over https an open padlock (orange, strokes about #E93700) on a
  22 pt tile, 4 pt in from the pill's left and top, orange at about 10 %, replaces the magnifier;
  while a first response is awaited the magnifier is back. Cra: `LittleAddress` (CraCore).

### Live re-fit against Victor's full-screen screenshots (24 Oct, 20:21)

Victor's side-by-side screenshots (Cra and Arc both at 1728×1084, each with the other
browser behind it) showed Cra's sidebar 6–17/255 darker and more saturated than Arc's at
every height except the very top, and Cra's row text pure black where Arc's is warm.
Sampled at x=500 px (2x), y = 160 / 700 / 1200 / 1700:
- Arc live: 134 131 98 · 149 139 102 · 151 136 99 · 163 139 103
- Cra before (lift 0.03): 128 121 86 · 137 125 89 · 143 127 91 · 146 126 90
- Cra after (lift 0.12): 139 134 100 · 152 141 106 · 160 143 108 · 162 141 108
Changes: `CraTuning.liftActive` 0.03 → 0.12; light-theme `textPrimary` = first theme colour
at 13.5 % brightness (`SpaceTheme.inkColor`, Victor → 33/28/11; Arc samples 32/26/0);
`textSecondary` black 0.58 → 0.50 (Arc's space header samples 75/74/57 over 150/138/100).
Folders: Arc draws `folder.fill` in the theme colour pulled 80 % to white (250/238/194)
under a `folder` outline in the toolbar colour (107/87/9); the old blue folder was wrong
for this theme. The blur reads ~70/255 lighter for the first second after launch (vibrancy
not yet active), so sample only after the window has settled.

### Picture in Picture (24 Oct, late evening)

Method: `strings` on Arc 1.168 and its ArcCore framework, `assetutil --info` on
ARC_PictureInPicture.bundle, Arc's defaults, and window captures / 120 Hz screen recordings of
Arc's PiP window driven with synthetic mouse events (file:// test page, w3schools mov_bbb.mp4,
the Extensions ▸ Picture in Picture menu item and the page's own `requestPictureInPicture()`).

- [O] Arc wraps Chromium's video PiP: ArcCore has `arc::VideoPiPCoordinatorImpl(content::
  VideoPictureInPictureWindowController*)`, the Swift `PictureInPicture` module has
  PIPWindowController/PIPWindowContent/PIPOverlayHostView, Controls with PlayControls and
  MeetingControls view models, DocumentPiPWindowController for document PiP, and
  WindowState+GoogleMeetAutoPiP (injected JS that clicks Meet's own PiP menu item).
- [O] Strings: setting "Enable Picture in Picture when you leave a video tab"; menu "Picture in
  Picture" under Extensions (no shortcut); command bar "Open Picture in Picture"; tooltips
  "returns to the original tab", "closes the pip window", "minimizes the pip window", "Skip back /
  ahead 15 seconds", "Drag upwards to seek precisely", "Keep Window on Top", "Open automatically";
  assets GoBack/GoForward (54 pt) and meet-pip-chat-(un)selected. Feature flags useChromiumAutoPiP,
  useChromiumAutoPiPForGMeetOnly, disableAutoPipGlobally, autoPictureInPictureOnWindowOccluded.
  Analytics: pictureInPictureModalShown/Closed/Minimized/BackToTab, pictureInPictureSharedTabSwitched.
- [O] Window: level 3 (NSFloatingWindowLevel), borderless, no title bar, standard window shadow,
  corners whose alpha ramp is 41/93/138/174/197/216/226/235/241/247/251 over x = 7…17 px at 2x and
  3.5 px on the diagonal = a 6 pt continuous corner. 782×440 for a 16:9 video on this 1728×1117
  display, first shown 10 pt from the top and right of the visible frame. `LastPiPPosition`
  (defaults, JSON) stores `{"screen":{"_0":{"topRight":{}},"_1":[782,440],"_2":0}}` and switches to
  `{"absolute":{"_0":[[x,y],[w,h]]}}` (bottom-left origin) once the window has been handled.
  Cra (#316) saves the display too (`CraPictureInPictureDisplay`, its CGDisplay UUID, and that display's frame):
  the next video opens on the display it was left on, even when Chromium opens its window on another one and after
  the displays are rearranged; with that display unplugged, Arc's top-right corner of the display in use.
- [O] Appears in a single frame (120 Hz recording: luminance over the window area jumps from
  20.7 to 138.5 between two consecutive frames; no scale or fade).
- [O] Nothing is drawn on hover, click or Space-pause: captures at 0, 0.3, 0.8, 2 s after
  entering with slow and fast pointer sweeps, after clicking the window (it becomes key; a 10×10
  helper window appears at 0,1107) and after pausing with Space are pixel-identical to idle apart
  from the video. The tooltips above prove controls exist; whatever reveals them was not found
  with synthetic input, so Cra draws nothing on hover either. [U] Their layout.
- [O] Closes as soon as the window its tab lives in becomes key again (also for a PiP the page
  started itself). The AX tree of the window is empty (AXSystemDialog, no children).
- [O] Arc's Extensions ▸ Picture in Picture does nothing on a page whose video has not started.

Cra: Chromium's PiP window (class NativeWidgetMac…, title "Picture in Picture", level 3, default
384×216 bottom-right, Chrome's hover controls) is reshaped by `PictureInPictureChrome`: opaque off,
6 pt continuous corner mask on the content view, Arc's frame, and a transparent child window on top
that swallows the pointer (so Chrome's controls never appear) and does dragging / aspect-locked edge
resizing; the frame is remembered in UserDefaults like Arc's LastPiPPosition. Measured on Cra: the
corner alpha ramp and the shadow extents are identical to Arc's capture, pixel for pixel.
Chrome's own window ignores the pointer and has `preventKeyWindow` set (2 Nov): it keeps a 4 pt
resize band outside its frame that the overlay doesn't cover, and once key (a drag on that band, or
AppKit picking it when a click activates Cra) Chrome shows its ±10 s controls on focus and on every
mouse move, under Cra's ±15 s ones.
Pressing the overlay (3 Nov, #134, `PictureInPictureGesture` in CraCore): the buttons take clicks
whether or not the controls are faded in, a press moves or resizes only past 3 pt of travel (a click
on play used to nudge the window by its drift), edges are 8 pt deep with 16 pt corners like
Chromium's, and a resize keeps the opposite edge or corner where it was (the vertical anchors were
inverted, so the top edge stayed put while the bottom was dragged). The cursor comes from a tracking
area over the same zones (cursor rects only work in a key window, and the overlay never is one), and
while the pointer is over the window Cra sets "SetsCursorInBackground" on its WindowServer
connection, so the resize cursors show with another app in front too (verified with `screencapture
-C` over each edge and corner, Finder in front and Cra in front). A press with Cra in the background
already reached the overlay (acceptsFirstMouse lets it through; since #206 it no longer activates Cra);
without the cursor it only looked dead. Drags are measured from each
event's own screen location; `cra.log` gets `pip: move`, `pip: resize <edge> from W×H`, `pip: resized
<edge> W×H → W×H` (with "asked" when Chromium kept another size) and `pip: overlay has no parent window`.
Swiping (4 Nov, reported on X): Arc's PiP follows two fingers on the trackpad and is thrown into a screen corner;
its placement enum is `screen(corner) | offscreen | absolute(rect)` with corners topLeft/topRight/bottomLeft/
bottomRight next to spring presets firm/firmSlow/springy… (strings, Arc 1.171). [U] Its spring and how far a
throw carries were not measured. Cra (`PictureInPictureThrow`, `PictureInPictureFlight` in CraCore): the window
follows the scroll deltas (direction from `isDirectionInvertedFromDevice`), the speed of the last 80 ms projects
the resting point with UIKit's 0.998/ms deceleration, the nearest corner of that screen's visible frame (10 pt
in) is the target, and a critically damped spring (response 0.4 s) flies it there from the fingers' speed.
AppKit's momentum events are ignored; a plain wheel moves nothing. `cra.log`: `pip: swipe to <corner> at N pt/s`.
Over another app's full-screen Space (6 Nov, GitHub #206):
- [O static] Arc's `PictureInPicture.PIPWindowController` subclasses `ARCUI.MovableWindowController`, and
  `ARCUI.MovableWindow` subclasses `NSPanel` (`otool -ov`, Arc 1.171). Its AXSystemDialog subrole (above) means
  `.nonactivatingPanel`, the same kind of window as Little Arc (see "Little Arc over a full-screen app").
  [U] Arc's collection behaviour, and Arc on screen over a full-screen app.
- [O, Chromium source] Chromium's video PiP (`VideoOverlayWindowViews::Create`) and Document PiP (`BrowserWidget`,
  TYPE_PICTURE_IN_PICTURE) are ordinary NativeWidgetMacNSWindows at kFloatingWindow with
  `visible_on_all_workspaces`, which is `.canJoinAllSpaces` only. Chromium floats Glic's panel and the
  screen-share picker over full-screen apps with `Widget::SetActivationIndependence` (NativeWidgetMacNSWindow
  `setActivationIndependence:`, which answers `_isNonactivatingPanel` and turns canHide off) plus
  `SetCanAppearInExistingFullscreenSpaces` (adds `.fullScreenAuxiliary`).
- [O, stand-in app + Spaces probe] With another app full screen, a background app's floating `.canJoinAllSpaces`
  window is missing from that Space. It is still missing with only `.fullScreenAuxiliary` added, or only
  `_isNonactivatingPanel`. With both it is there, and so is a borderless `.nonactivatingPanel` NSPanel with
  `.fullScreenAuxiliary`; canHide doesn't matter. `.managed` keeps it off whatever else is set, and Chromium makes
  every top-level window managed (Document PiP's had 37: canJoinAllSpaces, managed, participatesInCycle). Flags
  changed while the window is on screen take effect at the next Space switch. If the full-screen Space is already
  in front, they take effect only once the window is ordered again (`orderFrontRegardless`).
- Cra (`CraCEFRuntime.floatOverFullScreenSpaces`): Chromium's recipe without `.managed` on its video PiP window
  (from `PictureInPictureChrome.style`) and its Document PiP window (found from the ownerless CraClient's
  OnAfterCreated), with canHide kept on so ⌘H still hides it. The window is ordered again when visible, and the
  overlay is a borderless non-activating NSPanel. Measured on a test copy with a full-screen stand-in app in
  front: main had video and Document PiP off that Space. Now both are on it, so is a video PiP opened while that
  Space is in front, and a click and a drag on it keep the full-screen app frontmost and its Space active.
Chrome's origin strip (8 Nov, GitHub #246): Chrome draws its title strip (favicon, host, top scrim)
for 5 s after the window appears and then keeps it until a click or key press reaches its window,
unless the page is trusted for media playback (file://, or high media engagement;
`VideoOverlayWindowViews::UpdateControlsVisibility`). The 24 Oct captures used a file:// page, so
the strip went after about two seconds; on YouTube it never went, because Cra's overlay takes every
click. CraCEF enables `VideoPipForceTrustedForMediaPlaybackForTesting` (it only feeds that check), so
the strip never shows: on an http page it is absent at 0.5 s and after 10 s (captures of a test copy).
Arc 1.172 binary (otool/llvm-objdump on the arm64 slice, 8 Nov, #246):
- [O static] Position keys are now `LastVideoPIPPosition` / `LastDocumentPIPPosition`. No fixed default
  size: `.screen(corner, size: nil)` keeps the window's current size inside the limits, 10 pt in. The
  first size most likely comes from the video's rect on the page [I]. Limits: at least 224×126 scaled
  to the content's aspect (a 16:9 window is 224×126 at its smallest, which is the 223×125.5 the #246
  reporter measured), at most max(224, 0.617 × screen width) × max(126, visible height − 20).
- [O static] Hover layer: one flat `Color.black.opacity(0.33)` scrim, `.easeInOut(duration: 0.2)` in
  and out; the controls fade with it. Buttons press-scale to 0.95.
- [O static] Size classes by width: tiny < 280, small < 400, normal < 600, large. Controls 12 pt in when
  tiny, 16 pt otherwise, button padding 8 (10 from 400 pt): glyph centres 26 / 30 / 32 pt from the
  edges (the reporter measured 26 on a tiny window). Back to Tab is a pill top-left, 12 pt medium
  words from 400 pt wide, 6 pt continuous corners. Minimize and Close are a group (top-right [I]),
  glyphs with tooltips only. The address centred between them is from the reporter's captures; no
  host label was found in the binary.
- [O static] Minimize is per site (`minimizeEnabled` in its PiP config) and asks Chromium to leave PiP;
  `offscreen` is a separate "stash" past the screen edge. Cra has neither.
- [O static] Scrubber: 5 pt capsule (15 pt drag area) 8 pt above the bottom (4 when tiny), white over
  white 30 %; dragging upwards slows seeking by 2^round(dy / 60 pt), down to 1/16. Cra draws it
  (`PictureInPictureScrubber` in CraCore, 12 Nov) for a video with an end, and a press goes to that
  spot. [I] The side insets (12 pt tiny, 16 otherwise, as the other controls) and the press-to-seek
  are not from the binary. Cra's band leaves the bottom 8 pt to the window's resize edge.
  [O static] (12 Nov, PR #384 review) Arc's `BasicScrubber` (module PictureInPicture) keeps
  `dragStartTime`, `dragStartLocation`, `relativeTranslation`, `totalTranslation`,
  `wasPlayingAtDragBegin`, `_scrubSpeed`, `barHeight`, `draggableHeight`, `_hovered`; a
  `ScrubSpeedLabel` view sits with `PlayControls`, and the per-site config has `_scrubEnabled`. Cra
  pauses a playing video while the scrubber is held and plays it on after (from
  `wasPlayingAtDragBegin`). [I] The relative translations suggest a drag moves from where the video
  was rather than jumping to the press; whether a plain press seeks, and the speed label's words
  and look, are not settled: Arc's hover controls don't show while a script drives the pointer with
  Arc in the background, and its PiP window hides when Arc is made active.
Cra follows the limits, the scrim, the fade, the insets and the Back to Tab words
(`PictureInPictureLayout` in CraCore) and keeps its 782×440-on-1728×1117 opening size.
Double click (11 Nov, reported by a user): a double click on Arc's window returns to the video's tab.
[O live] Arc 1.172.2, 12 Nov (PR #383 review): a real double click (cliclick) on a 242×136 PiP window
of a playing file:// video took the window away and the page's video played on; a single click on
the same window just before did nothing. Cra (`PictureInPictureGesture.returnsToTab`): the second click of a double click that stayed
a click, anywhere outside the buttons, does what Back to Tab does; `cra.log` gets `pip: double click,
back to tab`.
Centre controls (8 Nov, GitHub #262, from the #246 reporter's Arc crops): play/pause only, glyph
about 23.5 pt, at 224 and 277 pt wide; the ±15 pair in ~31 pt circles and a 37–40 pt play/pause at
396 and 801 pt, so the skips arrive with the small size class (280 pt). Cra: play 28 pt symbol
(22 × 26 pt of ink) when tiny, 44 pt (35 × 39) from 280, skips 28 pt (30 × 32.5)
(`PictureInPictureLayout.centreControls`). Chromium's own controls showed under Cra's when its
window became key: `NativeWidgetMacNSWindow.preventKeyWindow`, which Cra sets, is also written by
Chromium (`orderFrontKeepWindowKeyState` sets it, and clears it after the next Space change), and
`VideoOverlayWindowViews::OnNativeFocus` shows the controls. Cra sets it again on activation, Space
changes and resizes, and hands the key back if the window takes it anyway (logged as `pip:
Chromium's window became key`).

Chromium only enters PiP from a page holding a user activation. `CefBrowserHost::SendKeyEvent`
never reached the page in Chrome-style hosting (CEF 154), so Cra sends an F19 key down/up straight
to Chromium's `RenderWidgetHostViewCocoa` (the view AppKit gives real key presses to); the page sees
`keydown F19` with `navigator.userActivation.isActive = true`, and the injected script requests PiP
once activation is reported. (Until 26 Oct test videos had to be VP9/Opus WebM: Spotify's CEF build
has no H.264/AAC. Cra now ships its own CEF build with them; see docs/release.md.)

### Hover, toolbar colour, library glyph (24 Oct, late evening)

- Row hover (pointer moved onto "Google Search Console", screen capture, same backdrop):
  Arc 220/210/171 → 210/200/163, i.e. the row darkens by ≈4.5 % black. Cra's `hoverFill`
  was white 38 % (lightening); now black 4.5 % on light themes. The active favourite keeps
  its white 38 % fill explicitly.
- Toolbar colour: Arc tints the bar from the page (theme-color meta, else the page
  background). Cra's probe had an unreachable body/html fallback (a `__none__` sentinel was
  set first), so pages without a meta tag got the space tint. Fixed: meta → body
  background → html background → white. Cra's New Tab page now gives a 34/34/34 bar.
- Library glyph: `LibraryButton` composes `archivebox.fill` with a cloud, dot and triangle
  puff; Arc's box has no lid line, otherwise the same silhouette at 14 pt.
- `liftActive` settled at 0.10 (0.12 read 2–9 lighter than Arc mid-sidebar).

### Split View, observed live (Arc 1.170, 24 Oct 2026, late evening)

Window captures of Arc's main window while driving it (menu clicks, synthetic drags), compared with Cra's
isolated test instance; composites in docs/screenshots/compare-*.png.
- [O] "Add Split View" on a selected tab: the new empty pane appears fully laid out within one frame (window
  frames at 27 fps); the command bar fades in over the new pane, horizontally centred on it but kept inside the
  window (right margin ~80 pt), with Arc's "Search or Enter URL…" new-tab bar, not the edit-URL bar.
- [O] Pane cards: 10 pt gap, both cards rounded; each pane has its own toolbar with ← → and a close ✕ at the
  right; the focused pane additionally shows a split-options button (rectangle.split glyph) just before its ✕.
  The URL is centred; in narrow panes the link glyph is dropped. (These panes were ~215 pt wide, too narrow for
  ↻ and the sliders: see "Split pane bars and the focus ring" below, GitHub #178.)
- [O] The empty pane is the window gradient plus a white veil of about +9/+11/+12 per channel (≈ 0.2 alpha),
  with a hairline under its toolbar.
- [O] Hovering the gap between panes shows no handle. Dragging from the gap did not resize in our runs: Arc
  entered its pane-drag mode (whole window content scaled down, a translucent drop region with a thin border
  opened at the target slot) and on release a duplicate pane was inserted. Divider resize therefore remains
  [U] for exact feel; Cra resizes with a plain pan, snaps at 50/50 and resets on double-click (from the
  recovered PaneResizeState).
- [O] Dragging a sidebar tab over the content: the entire window content shrinks (~0.92) and a lighter,
  bordered drop-region card opens at the edge nearest the pointer; dropping inserts the tab as a pane.
- [O] Splitting a favorite (YouTube) with a dropped pinned tab (Umami) left both in their sections and created
  a Today split item showing "YouTube | Umami"; a second drop produced "YouTube | Umami | Umami" (copies, not
  moves). While a new pane is still empty the sidebar shows it as a plain "New Tab" row in Today; the split
  cell appears once the pane has a page.
- [I] The pinned tab a split copied goes to sleep in Arc, so its video doesn't also open in Picture in Picture
  (a user's report on X, 4 Nov, ⌥Return in the command bar on a pinned YouTube tab; not observed here). Cra discards
  the pinned tab's page when its copy comes on screen (`BrowserManager.hibernate`, sleep reason `splitCopy`,
  scenario split-pinned-video).
- [O] Sidebar split cell: one row, white rounded selected background, child segments (favicon + title) separated
  by hairlines, ✕ per child on hover.
- Cra status (this session): item model, store operations, multi-pane shell with per-pane toolbars and page
  windows, divider resize/snap/reset, Add/Close/Separate/Flip actions + View menu + ⌃⇧= / ⌃⇧−, command bar over
  the new pane, pinned/favorite anchors become Today copies, sidebar split row with per-child close and
  Option-click to unsplit, drop-on-row-right-half to split. Not yet: the drop-region placeholder over the
  content (CEF page windows receive the drag), the window shrink effect, and a 1:1 divider feel.

### Split pane bars and the focus ring (Arc 1.171, 4 Nov, GitHub #178)
Offline Arc (fake home, see "One space") with a Today split of two local pages, read over AX (button
descriptions and frames) at window widths 1400 → 926 (Arc's minimum), plus window captures and real-pointer hover.
- [O static] The bar's state has `onlyShowEssentialControls`, `isHovered`, a `blueprintType` of `onHover | always`
  (ContentToolbarInteractionTracker's hover session), and per-item `urlDomainHasRoom`, `numberOfExtensionsThatFit`,
  `refreshHasRoom`, `copyHasRoom`, `settingsHasRoom`. The ring is a `focusBorderLayer`.
- [O] Focused pane: Go back, Go forward, Reload this page | address (Copy Current URL, security glyph) | pinned
  extensions (in the reporter's capture; the offline copy has none), Site Control Center, Split View Menu,
  Close Split View Pane. Unfocused pane: Go back, Go forward | address | Close Split View Pane only.
- [O] Pointer over an unfocused pane's bar: Reload, Site Control Center and Split View Menu appear there too (the
  focused pane's set); the ring stays where it is. Pressing that Reload reloads the pane and moves the focus (and
  the ring) to it; the other pane drops back to the essentials.
- [O] Narrow: a 387 pt pane (window 1000) keeps everything; a ~350 pt pane (window 926) drops Reload, cuts the
  domain short ("....lvh.me") and keeps the Site Control Center; a 215 pt pane (Arc 1.170, above) has neither.
  A three-pane split pins it down: Reload at 392 pt, gone at 359; the Site Control Center at 325, gone at 292,
  where every pane (focused or not) also loses its Copy Current URL glyph.
- [O] Toolbar hidden (topBarURLEnabled NO, set before launch): a single pane has no bar; a split still shows every
  pane's full bar and ring, and View ▸ Show Toolbar is disabled while the split is open (Hide Toolbar likewise
  with the toolbar on). Arc forces the bars in a split.
- [O] Card shadow, single card and every pane: fitted on 1-px profiles of all four sides (light space, 2x) as a
  Gaussian edge, black 26 %, sigma 3.6 pt, 0.8 pt low; about 11 % darker beside the card, 17 % below, gone by
  ~8 pt. Not on an empty pane (not measured).
- [O] Ring: 2 pt (4 px at 2x), solid, along the card's rounded edge and over the bar's edge, in the space's
  `primaryColorPalette.shadedDark` (#6B5709 measured on Victor's yellow space, P3 capture; #B60222 vs Arc's stored
  #B70021 on the reporter's red space). None on the unfocused pane or on a lone pane.
- Cra: ToolbarComposition (`hovered`, essentials only on an unfocused, unhovered pane), ToolbarRoom (pins, then ↻,
  then the sliders and the copy glyph below a 100 pt address: 114 pt at Arc's 325 pt pane, 82 at 292),
  PaneCardView.focusRing (theme.shadedDark), and a ring panel over a page that lives in its own window (DevTools
  docked). A control on an unfocused pane focuses it first, as Arc's Reload does. ShellView.panesShowBars keeps
  the bars in a split with the toolbar hidden. CardShadowView: a 9-slice image, 31 % with a 6.5 pt Core
  Graphics blur (CG's blur is softer than its nominal sigma; refitted on Cra's capture to within ~2 % of Arc's
  profile per side). Pins before ↻ is from the non-split bar (ten pins, ↻ kept); the offline copy loads no
  extensions (`--load-extension` is ignored).

### Expand Current Split (Arc 1.172.2, live, 11 Nov 2026)
Victor's running Arc (1.172.2 refuses a second instance, and an ad-hoc re-signed copy aborts in CloudKit
at launch, so no offline copy): a File ▸ Blank Window (it gets a space of its own, nothing synced), a split
of three local colour pages, driven through AX menu presses with the command bar's field set over AX,
pane frames read from the AXWebAreas, window recorded with ScreenCaptureKit at ~80 fps. Window 1728×1084,
sidebar hidden, content 1708 pt wide.
- [O] Where: View ▸ Expand Current Split, after Separate Page from Split View (MainMenu.nib: action
  `expandSplitViewPane`, command-bar keywords "Expand; Expand Split View; Maximize"). No shortcut. The pane
  toolbar's Split View Menu doesn't have it (Move Left/Right, Add Right/Left Split, Separate Tab from
  Split, Convert to Vertical Split View, Share Split View…). The binary posts
  `maximizeFocusedSplitViewNotificationToken` / `maximizeCurrentSplitViewPane:`.
- [O] What it does: the focused pane takes the content area and every other pane drops to 220 pt. Two
  panes: 849 | 849 → 220 | 1478. Three: 220 | 1248 | 220 whichever pane is focused. The split stays a
  split: every pane keeps its bar (the small ones with the essentials), the focused one its ring.
- [O] How it's kept: as the split's width factors. StorableSidebar.json had `itemWidthFactors`
  [a, 0, b, 0, c, 1] after expanding c, so 220 is Arc's minimumPaneWidth applied to a factor of 0. It
  follows that a narrower window keeps the small pane at 220 (window 1200: 950 | 220, back at 1728:
  1478 | 220).
- [O] Animation: none. One recording frame shows 849 | 849, the next (≈13 ms later) 220 | 1478.
- [O] Getting back: there is no un-expand. The menu title never changes and a second Expand changes
  nothing. Expanding another pane (⌃⇧1 to focus it first) swaps them: 1478 | 220. Otherwise the divider
  (drag, or the double-click reset recovered from `handleDraggerDoubleClickGesture:`, not pressed here).
- [O] Stacked (Convert to Vertical Split View, middle pane expanded, 1064 pt tall): 210 | 614 | 220. The
  pane above a divider counts the 10 pt divider in its 220 (each stacked pane carries its own
  SplitViewBottomDraggerHandleView); the bottom pane has 220 of its own.
- [O] Add Split View on an expanded split (focus on the 1478 pane): the new pane takes a third of the
  focused pane's room (979 | 220 | 489, the new one at the end). Not built: Cra adds panes its own way.
- Cra: SplitPaneLayout moved into CraCore; `expanding(_:in:)` gives 1 and 0, the minimum is Arc's 220 (was
  200), stacked panes above a divider keep 210, and a divider drag starts from the lengths on screen.
  MainWindowController.expandSplitPane stores the factors (`setSplitWidthFactors`, like a drag), no
  animation. `cra://debug?paneLengths=<label>` logs the pane lengths; scenario expand-current-split.

### Pinned splits and the split menu (Arc 1.171, 30 Oct)
Observed live on a throwaway Today split (example.com | example.org), archived afterwards.
- [O] Tabs ▸ Pin Tab (⌘D) with a pane focused pins the WHOLE split (appended to Pinned); the item then reads
  "Unpin Tab" (the word stays "Tab"). Pressing a split row and releasing elsewhere drags the whole split:
  Pinned → Today moved both panes as one item. A pane never leaves by dragging; only through the menu or ⌥✕.
- [O] File ▸ Close Tab on an open pinned split closes the whole split (both panes stay pinned, nothing selected).
  The open pinned split's hover button is a minus (like an open pinned tab); a closed one shows ✕. The button
  sits once at the row's trailing end, not per pane (Cra still draws it per pane).
- [O] Right-click anywhere on a split row (either pane) shows one menu: Share Split View… | Separate All Tabs,
  Add Tab… (disabled while the split is closed), Convert to Vertical Split View | "Tab Options" header, one
  submenu per pane titled with its page (Separate from Split View | Share ▸, Mute, Copy Link, Copy link as
  Markdown | Archive Item) | Change Icon…, Rename… | Duplicate, Move to ▸ (spaces with a check on the current
  one, New Space…) | Archive Item, Archive Tabs Below (Today only). No Pin item.
- Cra (30 Oct): split rows drag as one item, ⌘D pins/unpins the split, ⌘W closes a pinned split as a whole,
  the menu follows Arc's minus Share/Change Icon/Duplicate, pinning makes each pane's page its home, and a new
  pane in a pinned split takes its first page as home.

### Clear cookies / cache (Arc 1.171, 30 Oct)
- [O] Command bar: "clear" lists Clear Cache and Refresh (selected, above the typed row), then "clear", then
  Clear Cookies and Refresh; "clear cook" puts Clear Cookies and Refresh first; both rows use a trash glyph.
  "cache"/"cookies" alone don't surface them. View menu: Force Refresh the Page, Clear Cookies and Refresh,
  Clear Cache and Refresh. Strings: "Clear cookies and refresh the current page." (site-scoped).
- [O] Arc lists a matching command above the typed row in general: "sett" → Settings, "new" → Add Split View,
  "clear" in a main window → Clear Unpinned Tabs. Pages/history follow a confidence rule not reproduced.

### Space header ••• and the space menu (Arc 1.171, live, 1 Nov, issue #40)
- [O] Header hover: the row's geometry, glyphs and colours are under "Space header row" (#39) below, and Cra
  follows those. Here also: `sidebarSpaceEditButton` (AX "More", 2×26 pt until hovered, then 26×26) is the •••,
  centred 18.5 pt from the fill's trailing edge on a 24 pt hover tile; fill, chevron and button appear in one
  frame, no fade. An Icon-tab glyph sits in the emoji's 26 pt box 5 pt in.
- [O] The ••• and a right-click on the header open the same menu, as a context menu at the pointer (a click
  at 683,150 put the menu window at 684,144): Change Space Icon…, Rename Space…, Edit Theme Color…, Set Profile ▸
  (profiles, ✓ on the space's, then New Profile…) | New Folder, Live Folders ▸ (GitHub ✓ when present) |
  Share Space…, Export “<name>” into Folder ▸ (every space, its own disabled) | Manage Spaces… | Delete Space.
  The header keeps its hover look while the menu is open. Cra leaves out Share Space… (Arc's servers).
- [O] Rename Space…: the name turns into a selected text field and the ••• into a grey "Done" (10 pt semibold,
  `Sidebar space header done button`, 32×26). Export … into Folder deletes the space afterwards
  (`completeDeleteSpace`, "Space turned into folder"). Delete alert: "Delete your <name> Space?" / "This will
  archive all the tabs and folders inside it."
- [O] Change Space Icon…: an NSPopover (298 × 298 window, 272 pt content) under the icon, arrow up: Emoji | Icon
  segmented (105 × 23) and a trash button; a 254 × 27 search field; an 8-wide grid on a 31 pt pitch opening on
  the current emoji's row, the current emoji on a 27.5 pt tile; a hairline and 8 category glyphs. The Icon tab
  has no search: 56 white glyphs, 7 rows of 8, a 29 pt hover tile.
- [O] Set Profile ▸ New Profile…: Arc's own 450 × 426 dialog (#161C2F, ~24 pt corners) centred on the window,
  which dims to about (25,25,25) at 65%: profile glyph, "Create a new Profile" (17.5 pt), the "Profiles make
  your Spaces truly separate…" copy (14 pt, 18 pt lines), "What do you want to call this Profile?", a 49 pt
  field (placeholder "Personal"), "Profiles are **not synced** between computers.", Cancel `ESC` / Next `↩`.
- [O] Manage Spaces…: the Library on its Spaces page (`spaceManager`): one 240 pt card per space in its own
  theme, 24 pt apart, 27 pt after the rail, 48 pt from the window's top and bottom; the icon, name and a brush
  on a row 25 pt down, the pinned/Today list from 64 pt (no New Tab row), a move handle and ••• 21 pt above the
  bottom; a 29 pt blue + 34 pt after the last card. The sidebar widens to fit (744.5 pt for two spaces).
- [O] Edit Theme Color…: SpaceStyleEditor in a 382 × 534 window against the sidebar's edge at the window top
  (card 355 × 503, 14 pt in): a 340 pt dotted pad with Auto/Light/Dark (sparkles/sun/moon, the chosen one on a
  32 pt tile) and −/+, "Tap to pick a color for this space" while it has none; nine 24 pt swatches 29.5 pt apart
  between arrows (#F1EAE5 #E69FBA #9E749B #E1686F #EF8C62 #F2D66D #73E59C #7FB8D6 #666786); a 224 × 15 pt wave
  slider and a dotted dial.

### Profiles and spaces: who shares cookies (Arc 1.171, live in a fake-home copy, 3 Nov)
- [O] A space's cookies, logins, history and extensions are its profile's. Every space is on Default
  (`"profile": {"default": true}`) until it is moved; spaces on one profile share sign-ins. There is no
  setting for "cookies per space": Settings, Spaces menu and space menu only pick a space's profile.
  Victor's own Arc: both spaces on Default. Favorites are per profile too (topAppsContainerIDs).
- [O] New Space… (sidebar "Create a Space": Space name…, `Profile [Default ▾] ⓘ`, Choose a Theme,
  Create Space / Cancel) preselects the focused space's profile: AX `Profile, Work` from a space on Work,
  `Profile, Default` from one on Default.
- [O] Spaces ▸ Change Profile: a 450 × 338 sheet, the space icon on a 62 pt #4049DC tile with the
  profile badge, "Change **<space>’s** Profile", "Each Profile has different browser data, so you might
  get logged out of some websites, see different Favorites up top, or need to re-install extensions.",
  "**<space>’s** Profile" + a #2E36E7 pill (`spacePicker`; 14 pt #BEC0F3 circle with the chevron in
  the pill blue, the name in #BEC0F3) opening an NSMenu Default | other profiles | — | New Profile;
  Cancel `ESC` / Change Profile `↩`. Change Profile with New Profile opens Create a new Profile.
- [O] Create a new Profile ▸ Next ▸ "Which Spaces should use this Profile?" (450 × 506): "These Spaces
  will start fresh in your brand new Profile — so you’ll have to log back in to websites, re-save your
  passwords, add extensions, etc. You can always switch back to your previous Profile though if you
  forgot something!", one 63 × 95 theme card per space 76 pt apart, a 16 pt circle under each (#5B616F
  ring; #007C00 with a tick when chosen, the space it was opened for already ticked), the name;
  Back `ESC` / Create Profile `↩`.
- [O] Settings ▸ Profiles: "Your Profiles" with "N Space" counts and + / − / rename; per profile Search
  engine, Search Settings…, Include search engine suggestions, Archive tabs after (asks "all of your
  Profiles, or only your X Profile?"), New documents, Download location, and Privacy and Security,
  Passwords, Credit Cards, Notifications, Clear Browsing Data.

### One space (Arc 1.171, static)
- [O strings] Defaults key `showSpaceHeaderOnSingleUnnamedSpaces` (+ `…DidChange` action); the space context
  menu has "Show Space Header" / "Hide Space Header" ("Menu item to toggle space header visibility").
  Cra: Hide Space Header on the header's menu with one space, Show Space Header on the list's menu, and
  Settings ▸ Tabs ▸ "Show the space header with only one space"; hidden also drops the dock's lone icon.
- [O] One-space Arc, run live 31 Oct without risking sync: `CFFIXED_USER_HOME=<fake home>` with a trimmed
  StorableSidebar.json (one untitled space, nothing pinned) plus the Storable{AuthState,FeatureFlags,
  EducationState,MembershipCard,DefaultBrowserPrompts,KeyBindings}.json copies, launched as
  `sandbox-exec` (deny network-outbound ip/tcp/udp) `…/MacOS/Arc --no-sandbox`. Without `--no-sandbox` the
  GPU process dies (nested seatbelt) and Arc never orders its windows in. Traps: cfprefsd ignores the fake
  home, so the copy writes the REAL company.thebrowser.Browser domain (back it up, restore after); `open -a
  Arc` while the copy runs launches the real Arc; File ▸ New Window over AX opens a window. Arc 1.172.2
  (10 Nov 2026) refuses to start while another Arc runs, so this needs the user's Arc quit first.
  "Unnamed" means no title AND no icon: a space with an emoji shows "Space 1" and keeps its header,
  however the defaults key is set. Drop `customInfo.iconType` too and Arc hides the header by itself.
  `topBarURLEnabled` (real domain) puts the URL field in the sidebar; the favorites card closes over AX
  (`sidebarFavoritesEmptyStateDismissButton`, writes `topAppsEmptyStateDismissedForProfiles`).
- [O] Measured (2x px, URL field in the sidebar, 31 Oct). Everything under the favorites is placed from the
  tiles' bottom, or with none from the URL field's; the favorites block (8 pt gap + tiles) takes no room
  when empty. Divider line below that point: header shown 54.5 pt; hidden 15.5 pt (no favorites) or
  18.5 pt (favorites). Header cap tops 21.5 pt below it either way. Every pinned row takes 41 pt, the
  first one too; nothing pinned takes none. Line → first Today row 11.5 pt. Cra matches all eight
  combinations of header × pinned × favorites to the pixel (SpaceColumnView.place, SpaceListView.layoutRows).
  Left: Arc's header title sits ~1 pt lower and reads slightly larger than Cra's (fixed 1 Nov: 13 pt semibold, header fill 36 pt).

### Favorites empty state (Arc 1.171, live, 3 Nov, issue #157)
- [O] Offline two-space Arc (fake home, no favorites), sidebar 228 and 300 pt, 2x window captures. A profile with
  no favorites shows a card where the tiles go (AX: `sidebarFavoritesCollectionView` holds it, ×
  `sidebarFavoritesEmptyStateDismissButton` "Dismiss"; closing writes `topAppsEmptyStateDismissedForProfiles`).
- [O] Geometry, from the first tile's top-left (8 pt in): fill 93.5 pt tall, the column's width, circular 12 pt
  corners; a 1 pt dashed line just outside it (5.5 on, 4.5 off). The space header sits 4 pt lower than under a
  row of tiles. Badge: a 16.2 pt circle (`star.circle.fill` 16 pt) centred 19.75 pt down; title 13 pt semibold,
  frame 33.5–49.5, 10 pt in from both sides; subtitle 11 pt, two 15 pt lines in a frame 150 pt wide at both sidebar
  widths, from 53 pt; × (`xmark` 10 pt semibold) centred 15 pt in from the top-right corner.
- [O] Tones: the subtitle and × are the title colour at 70%; the line is the badge colour at 30%. Light theme:
  badge = the toolbar's dark theme shade, star = a cream, fill = white ~0.14 over the sidebar. Dark: badge ≈
  white 0.92, star = a dark theme blue with a soft glow of its colour around the badge, fill = black ~0.135.
- [O] No hover state on the card or the ×. A tab dragged over it: the line turns solid, the fill lightens
  (white ~0.32 on the light theme), everything inside drops to 50%. A drop puts the tab in as the first tile; the
  × hides the card. Both change the layout in one frame (60 fps recording), no slide.
- [O] A multi-tab selection's menu has no Add to Favorites (Copy Links, Share 2 Items…, Change Icon…, Mute, Open
  in Split View, Duplicate, Move to, New Folder with 2 Items, Archive Tabs…). Issue #356's screenshot of two
  Today tabs, in sections: Open in Split View, Duplicate | Copy URLs ⇧⌘C, Share 2 Items… | Move to ›, New Folder
  with 2 Items | Change Icon › (dimmed), Mute | Archive Tabs. Cra: PickedTabsMenu.
- [O strings] Arc 1.17x binary: Share N Items… strings: "Generating Link...", the toast "Copied Shared URL" (live it said "Copied Folder URL")
  ("Letting user know that the sharable URL has been copied"; `itemsToShare`); Move to is "Menu Item that shows a
  user's root spaces in a submenu" (SidebarMenu+MoveMenu.swift, which also has "Move selected items to a new folder
  in a subspace"); the archive row is "Archive sidebar items"; Copy links/item links as Markdown exist as titles.
- [O] Arc 1.17x live, 11 Nov 2026 (Victor's Arc, read-only: ⌘-click, right-click, AX read, AXCancel). Two Today
  tabs: Copy Links, Share 2 Items… | Change Icon… (dimmed), Mute (dimmed, nothing playing) | Open in Split View,
  Duplicate, Move to ›, New Folder with 2 Items | Archive Tabs, Archive Tabs Below (dimmed). No ⇧⌘C on Copy
  Links any more. Move to ›: every space, ✓ on the picks' own, ──, New Space…. With a pinned tab added (3 picks):
  Copy Links, Share 3 Items… | Open in Split View, Move to ›, New Folder with 3 Items | Archive Items. AX also
  lists Archive Other Tabs and Archive Tabs Above in the Today menu, which are not drawn (hidden rows).
- [O] Same Arc, with five throwaway example.com tabs (opened through Little Arc ▸ Open in Victor, archived after):
  - The "pinned tab" of the short menu above was an Easel ("Test", `easelID` in StorableSidebar.json). An Easel among
    the picks gives the short menu and Archive Items; a real pinned tab doesn't.
  - Pinned tab + Today tab, right-clicked on the pinned row: the full tab menu, ending in Archive Tabs (no Archive
    Tabs Below). Archive Tabs then archived both at once, the pinned one too, no confirmation and no toast.
  - Five Today picks: the full menu, Open in Split View shown but dimmed, Share 5 Items…, New Folder with 5 Items.
  - Share 2 Items… opens a sheet over the window, not a toast: envelope badge, "Send this Folder to anyone, on any
    browser.", "Anyone with this link can view your Folder. Viewers won't receive future updates and this permalink
    cannot be deleted.", a "Never show me this again." checkbox, Cancel (ESC) and Copy Link to Folder (↩). Cancel
    pressed; the link was not made (it would be a permanent arc.net page showing the user's display name).
  - A plain click on a picked row that is also the open tab starts renaming it.
- [O live] Arc 1.172.2, 12 Nov 2026 (issue #386, a Blank Window of throwaway example.com/org/net tabs, two of them
  ⌘-picked): View ▸ Add Split View (⌃⇧=) ignores the picks. It adds an empty pane beside the open tab and opens the
  command bar, as with nothing picked; the picks stay picked, and Esc closes the bar and the empty pane. Arc has no
  key for the picks: Open in Split View in their menu is the only way to split them. Esc doesn't clear Arc's picks.
  Cra: ⌃⇧= unchanged; the menu row is pinned by Tests/Scenarios/picked-tabs-split.scenario.
- [O strings] The warning is Arc's Dialogs.SheetWindow (`showDialogSheetDeprecated(message:buttonTitle:icon:
  cancelButtonText:suppressionButtonText:informativeText:)`), "Alert title on privacy confirmation window for sharing
  tab collections": "Send this <type> to anyone, on any browser." with the type "Folder" for a folder and for picked
  tabs alike; the checkbox is "Toggle for showing the shared collections privacy dialogue". Arc also has
  "<type> currently private." and "Viewers need their own access to any site in this <type> that is unshared or
  requires authentication." (not seen).
- [O] The sheet at 2x (card 560 × 308 pt, #161C2F): envelope badge 62 × 49.5 pt at 48.5, 44.5 (fill #302F5C, 4 pt
  #6362A3 border with ~5 pt corners, 4 pt round-capped V flap, a 15 pt #6D6C96 postmark with two thin motion
  lines); title ink 120.5–138 from x 49; message 14 pt #888B98, ink 149.5 and 167.5, 18 pt pitch, wraps at 463 pt;
  checkbox 16 pt #2D3243 rounded square at 49.5, 195.5, label 13 pt #DBDCDF from x 79.5; buttons 243–281.5 tall
  38.5, Cancel 237–346.5 and Copy Link to Folder 354.5–532 (blue #3339F1). Cra: AppDialog.shareLink (`older`
  layout, ShareEnvelopeIcon, DialogCheckbox) lands within 0.5 pt everywhere (SwiftUI snaps the text rows to whole
  points); Arc's title runs ~3 pt wider.
- [O] Arc 1.17x live, 12 Nov 2026 (Victor's Arc, throwaway tabs, settings exported before and diffed after):
  - Ticked, the checkbox is Display P3 #397CF7 with a 2 pt white check; ticking it and pressing Cancel saves
    nothing (no defaults key changed, the sheet came back on the next Share).
  - Copy Link to Folder copies `https://arc.net/folder/<UUID>` and the toast says "Copied Folder URL" (top
    right), for picked tabs too; no "Generating Link..." was seen. The page is titled "2 Items" with "A Folder
    from <display name>" under it and the two links. Cra: FolderShareLink.picked titles its page "N Items".
  - With a picked tab playing sound, Mute is enabled; after Mute the row says Unmute.
- [?] Not measured: the drag-over fill on a dark theme, coloured dark themes (the star's colour there), 1x.
- Cra: FavoritesEmptyCard, dismissed per favorites container (WindowPrefs.favoritesEmptyStateDismissed, since
  Cra's favorites are per space). Badge, title, subtitle and × land within 1 px of Arc's at 2x. The dashed line
  runs on the fill's outer point, not just outside it: the card sits at the top of the space pager, which clips,
  so a line outside the fill lost its top edge.

### Space header row (Arc 1.171, live, 1 Nov, issue #39)
- [O] At rest: the space icon, then the title; nothing else. A space with an emoji shows it (the issue's
  Arc screenshot had none, most likely a space without an icon). Hovered: the row fills (white 0.10 on
  the dark JYSK theme), the icon is replaced by a down chevron in the same slot and a ••• button shows at
  the right end. Collapsed: the chevron stays and points right, hovered or not; the icon comes back only
  when the pinned tabs are expanded again. A click anywhere but ••• (title included) toggles the pinned
  tabs; the chevron turns a quarter counter-clockwise (down → right) over ~0.12 s; the hover swap and the
  fill have no visible fade (60 fps screen recording, variable frame rate).
- [O] 2x window captures, sidebar-relative points: fill 8 pt in from both sidebar edges, 36 pt tall,
  starting ~8 pt under the favorites tiles, circular corner radius ~12 pt. Icon/chevron centred on the
  favicon column (25.75 pt); title text starts at 44.5 pt. ••• hover square 24 pt, radius ~6, 6 pt in
  from the fill's right end, its own hover fill stacked on the row's. No tooltip on ••• after 2.8 s.
- [O] Pixel fits against SF Symbols / system font: chevron = chevron.down 12.5 pt bold (SSE 1.96; 12 bold
  4.18), ••• = ellipsis 13 pt semibold (SSE 0.07), title = system 13 pt semibold (SSE 0.02; Cra had
  14 medium). Dark tones (white alpha over the sidebar): title 0.45, chevron and ••• 0.59.
- [O] ••• opens the space menu at the pointer like a context menu: Change Space Icon…, Rename Space…,
  Edit Theme Color…, Set Profile ▸ | New Folder, Live Folders ▸ | Share Space…, Export "<space>" into
  Folder ▸ | Manage Spaces… | Delete Space. Cra's ••• opens its existing space menu (same as right-click).
- [?] Not measured: light-theme header tones, a space without an icon, 1x rendering (no 1x display
  attached), whether the fill needs the app active (one inactive-window frame showed chevron and •••
  without the fill).
- Cra: SpaceHeaderView matches all four states (rest, hover, collapsed, collapsed + hover) to within
  1 px at 2x; the ••• square sits 0.5 pt off so its dots land on Arc's.
- Cra deviation (4 Nov, X DM): collapsed, Cra keeps the space icon at rest and shows the right-pointing
  chevron only on hover, so the icon is always visible. A space without an icon keeps Arc's resting chevron.

### DevTools docking, Arc's way (25 Oct)

Evidence from Arc 1.170.0: the ArcCore framework (REA `inspect-macho`, sha256 0a51a5c7…) carries
Chrome's stock DevTools embedder strings (`&can_dock=true`, `setInspectedPageBounds`, `setIsDocked`,
`currentDockState`, `devtools_app.html`), and Arc's profile Preferences hold the frontend's own dock
and device-mode state (`currentDockState`, `emulation.device-mode-value`, `emulation.show-device-mode`).
Arc's main window exposes one AXSplitGroup around the page's web area. So Arc does no custom docking.
It runs Chrome's DevToolsWindow: the frontend runs with `can_dock=true`, draws the splitter, the
dock-side menu and the device toolbar itself, and tells the browser where the page goes
(`InspectorFrontendHost.setInspectedPageBounds`); the browser lays the page over that rect.

Cra does the same with CEF 154, which only offers DevTools as an undockable popup:

- The Chrome-style DevTools popup is reloaded once with `can_dock=true` (CraCEF `DevToolsClient::Prepare`).
- `setInspectedPageBounds` and `setIsDocked` are mirrored to the shell as console messages
  (`__cra_devtools_bounds:` / `__cra_devtools_docked:`); `setIsDocked` is acknowledged in JS and never
  reaches Chrome, so Chrome does not try to move the contents itself.
- The DevTools window spans the card body under the page; the page window is laid over the reported
  placeholder (`MainWindowController.pageRect(forBody:tab:)`), which keeps the placeholder's edge
  offsets while the card resizes. Splitter drags stream a new rect every frame (verified: 15 updates
  in 0.45 s, page reflowed live). Device mode, dock right/bottom/left all work; "Undock into separate
  window" turns the DevTools window into a normal floating window and the page fills the card again.
- Frontend helper popups (`device_mode_emulation_frame.html`) are blocked; a popup whose client is
  not a page client is no longer cast blindly (that cast crashed Cra on undock).

Two hosting bugs found on the way, both affecting every page, not just DevTools:

- Chromium lays its frameless window's content view 22 pt below the top (room for a hidden title
  bar), which left a white band above every page. The shell now sizes the content view to the window.
- Chromium's frame view derives from NSThemeFrame, so macOS clipped page windows to its ~18 pt window
  corner radius even when borderless (rounded page corners under the toolbar and against DevTools).
  `ChromiumWindowCorners` overrides the frame view's corner queries for docked page/DevTools windows
  only; the content layer's mask then gives the card's 6 pt bottom corners.

Debug aids: `defaults write dk.kildahl.cra devToolsLog -bool YES` logs the DevTools life cycle to
`$TMPDIR/cra-devtools.log`; `cra://debug?devtoolsjs=<script>` runs a script in the current tab's
DevTools frontend (used to toggle device mode, dock sides and drag the splitter in tests).

### Sidebar icons and the Ahrefs subtitle (25 Oct)

- Arc's `SidebarItemsFaviconCache` names each 32x32 PNG `md5(sidebar item id)` (218 of 226 tabs matched);
  Cra's Arc importer already copies these. Once a tab loads, both browsers show the live page's icon,
  so Gmail/Calendar favourites show Google's "G" in Cra only because Cra is not signed in to Google
  (the tabs sit on accounts.google.com). Signing in inside Cra fixes it; nothing to fake.
- Arc shows "ahrefs.com" under the renamed Ahrefs pin and nothing under TradeTracker. Arc's stored
  data for both is alike (custom title, savedURL equal to the live URL, no extra keys), the pointer
  was not hovering, so the rule depends on live state Arc does not persist; still unknown. Cra shows
  "id.tradetracker.com" under TradeTracker because, signed out, that tab redirects to the login host.

Chrome runtime session restore (25 Oct): after a run that did not quit cleanly (SIGTERM from a
test script, a crash) the profile keeps `profile.exit_type = "Crashed"` plus Default/Sessions, and
the Chrome runtime restores the last session into a stock Chrome window (title bar, location bar,
1200×1084 at 22,33) as soon as the first browser is created; marking the profile clean alone does
not stop it. CraCEF now deletes Default/Sessions and writes exit_type Normal before CefInitialize
(verified: SIGTERM, relaunch, no stray window). Verification captures for PiP live in
build/pip-verification (arc_/cra_ idle, hover, shadow, and compare_*.png).

### Same-backdrop calibration, 25 Oct 2026 (CraVis test instance, solid white/black behind)

Method: a renamed copy of build/Cra.app (`CraVis`, own `CRA_DATA_DIR` with Victor's prefs)
launched from the shell with `CRA_TUNING="lift=…&alpha=…&alphaTop=…&alphaBottom=…&material=N"`,
a full-screen solid window ordered directly behind the measured window, `screencapture -R`
of the sidebar strip, pixel runs at x=500 px (2x), y = 160/700/1200/1700/2100.
- Arc 1.170, Victor theme — white: 204/197/164 · 215/208/167 · 218/201/160 · 219/193/159 ·
  218/188/154; black: 123/116/83 · 139/124/90 · 146/129/89 · 154/128/94 · 159/129/95.
  So Arc = c + k·backdrop with k 0.32 (top) → 0.23 (bottom).
- Material responses with the gradient and lift off (black / white at 2x): hudWindow dark
  27 / 160 (passes 52 %), fullScreenUI dark 30 / 139, popover dark 33 / 121, menu 37 / 101,
  titlebar 52 / 97, selection 41 / 106, sidebar & underWindowBackground dark 41 / 83,
  hudWindow light 113 / 226, sidebar & underWindowBackground light 194 / 218, windowBackground
  and contentBackground opaque. Nothing passes more than hudWindow dark, and nothing bright
  passes much at all, so Arc's 32 % with a 123-level intercept is not reachable exactly.
- Final: hudWindow dark, lift 0.14, gradient opacity intensity×1.44 (0.36) at the top and
  ×2.22 (0.56) at the bottom, stops = the theme colours unchanged. Cra — white: 190/185/157 ·
  204/193/161 · 208/192/159 · 208/188/154 · 211/188/152; black: 118/114/87 · 135/124/94 ·
  144/128/96 · 150/132/98 · 157/135/99. Within 5 of Arc over black, 7–15 darker over pure
  white (≈6–8 over a mid-tone desktop). An additive (CIAdditionCompositing) lift was tried
  and misbehaves over the vibrancy layer (k jumped to 0.48); keep the alpha-white lift.
- Hover (pointer moved, same backdrop): Arc row 220/210/171 → 210/200/163, favourite tile
  207/194/166 → 197/184/158; Cra row 207/198/160 → 198/189/154 (same Δ), tile hover now
  black 9 % (was equal to the resting tile).
- Toolbar: white until the page reports a colour (meta theme-color, else body/html
  background, else white), as Arc.
- Sidebar toggle (⌘S) recorded at 60 fps with `screencapture -V`, per-frame mean |Δ| on the
  sidebar strip: Arc moves for 5 frames (108, 34, 15, 6, 1 → 66 % of the travel in the first
  frame, then a soft landing); Cra 5 frames (59, 160, 35, 13, 10; the first value is a
  frame cut by the keypress, so 79 % in the first two frames). Same length, same ease-out.
- Toolbar on the same page (example.com, 25 Oct): Arc's bar reads 34/34/34, i.e. the page's
  own colour, not a fixed white; Cra derives it the same way (meta → body → html → white).
- Final sidebar numbers (balanced): black 120/116/89 · 135/124/94 · 144/128/96 · 152/133/99
  · 160/137/100; white 193/188/159 · 204/193/162 · 209/193/159 · 211/191/156 · 214/190/155.
  Blend-mode lifts (CIAdditionCompositing above or below the gradient) blow out: in-process
  compositing never sees the window-server blur, so only alpha blending composes correctly.
- Same page in both (example.com via `cra://navigate` in the test instance, AppleScript
  `make new tab` in Arc): Cra's bar 34/34/34 over rows 20–100 px, Arc's 34/34/34 over 20–83
  with its 1 px 45/45/45 hairline. Library glyph redrawn as a lid-less 13×10 box with a slot
  under the confetti puff.

### Sidebar scrolling (Arc 1.170, 25 Oct 2026, AX tree + window-id captures)
- [O] Only the space's tab list scrolls. The AX tree puts favorites (window y 36–99) and the space page
  (y 99+, a 568pt-wide horizontal pager group) side by side; inside the page the header row (y 99–135) sits
  above an `AXScrollArea` 284×899 at y 135–1034 that holds the `sidebarAllTabList` outline. Scrolling it
  (AX scroll-bar value 0 / 0.5 / 1) leaves favorites and the "Victor" header in place.
- [O] Outline: a 3pt top spacer row, 41pt rows, the pinned/today divider as a 17pt row, and ~121pt of
  empty list after the last row (at full scroll the last row ends 121pt above the dock).
- [O] Edge hairlines: full sidebar width, 1pt, ~5% black over the light theme (227 → 216), top one at
  y 135 shown only while the list is scrolled away from the top, bottom one at y 1033 shown only while
  rows are hidden below the viewport (the trailing empty space does not count). Both fade over roughly
  0.2–0.3s (window captures 0.2s apart showed partial strength in the first frame).
- [O] Pinned rows scroll with Today (26 Oct, AX row frames): one outline holds pinned, divider and Today
  rows; at scroll value 1 the first pinned rows (Kildash, Phantom, Umami) sat above the viewport top while
  the header stayed. No sticky pinned section: no class implements `tableView:isGroupRow:` /
  `floatsGroupRows` (only a selector reference exists). Arc's way to keep a long pinned list out of the way
  is collapsing it from the space name. Cra keeps the single list (a pinned/Today split was tried and dropped).
- [?] Dark-theme hairline colour (no dark Arc sidebar on screen; Cra uses 7% white) and whether Arc keeps
  each space's scroll offset across space switches (Cra currently resets to the top).
- Cra: favorites and `SpaceHeader` are outside the `ScrollView`; its viewport measures 0,168 284×899 in
  AX, identical to Arc, and the hairlines land on the same pixel rows (270/271 and 2066/2067 @2x).
- Toolbar hairline: Cra now draws Arc's 1 px line under the bar on the card (white 5 % on
  dark bars, black 5 % on light ones); on example.com Cra reads 34 with 45 at rows 82–83,
  Arc 34 with 45 at rows 84–85 (Cra's line sits inside the 32 pt strip, Arc's just under it).

### Closing vs removing pinned tabs (Arc 1.170, 27 Oct 2026, field metadata + live hover recordings)
- [O static] `SharedWindowFeature.SidebarCellCloseButtonConfiguration { action, tooltip: String }` with
  `Action { deselect, close, unsplit }`; the tab cell state carries it as an optional, next to `canResetTab`,
  `resetTabTitle`, `resetTabIcon`, `closeItemShortcut`, `resetItemShortcut` and
  `shouldPerformUserAttentionAnimation`.
- [O live] Pinned tab that is the current tab: no button until hovered, then a **minus** (—) with the
  tooltip "Close and Keep Pinned ⌘W". Clicking it unloads the tab, keeps it pinned, selects the tab used
  before it (a Today tab here), scrolls the sidebar to that tab and flashes a dashed yellow ring around it.
- [O live] Any other pinned tab (here unloaded ones: Canteen plan, Dashboard): hover shows **✕** with the
  tooltip "Archive this tab". The ✕ removes the tab from the pinned section into the archive (going by the
  tooltip; not clicked, to keep Victor's pinned tabs).
- [I] A pinned tab that is loaded but in the background also gets ✕ (`deselect` only makes sense for the
  current tab; the one capture of a not-yet-current Temp Mail showed ✕). Not confirmed: Arc stopped
  taking synthetic input before that test finished.
- [?] Arc's pinned-tab context-menu titles (short Swift literals are inline in code, not in `strings`).
- Cra (TabRow): current pinned → `minus`, "Close and Keep Pinned (⌘W)", unload + reset + select the
  most recently active tab that is still open (closed pinned tabs are skipped, else two of them ping-pong); other pinned → ✕, "Archive this tab",
  `archiveTab`. Context menu: "Close and Keep Pinned" (only when open/loaded) and "Archive Tab". The URL
  tooltip moved from the row to the title so the buttons' tooltips show. No attention ring yet.
- Tooltips on these buttons (ArcTooltip module, field metadata): `ArcTooltipConfiguration { content,
  keyboardShortcut, preferredAnchor: .view(edge) | .cursor, presentationBehavior: .onMouseIdle(delay) |
  .immediate, maxWidth, colorPalette }`, `TooltipController { presentationTimer, lastTooltipDismissedAtTime,
  … }`. [O live, 1x recordings] Shown 1.60 s after the pointer's last move (two cases, 30 fps); moving
  straight from one tip to another control swaps at once; pops in with no fade, fades out in ~2 frames.
  Navy capsule 28 pt (the default theme's tones and ring, see "Space dock tooltip"), 12 pt medium text (fill 96 for "Canteen plan", 110 for
  "Archive this tab", 198 for "Close and Keep Pinned ⌘W"), 10 pt side padding, 7 pt text→caps, caps
  ~18 pt with a darker 2 px bottom band (~#777AD3), 3 pt apart (re-measured at 2x on 3 Nov: 19 pt, 6 pt from
  the text, 10 pt to the end; the 1x widths left out the ring's pixel on each side). Button tips hang off the bottom-trailing
  corner of a 16 pt box around the glyph (fill top-left = glyph centre + (8, 7)); row tips ("Canteen plan",
  the title) follow the cursor at +(13, 14).
- Cra: `ArcTooltip.swift` (`.arcTooltip(help)`, one shared non-activating child panel, `(⌘W)` suffixes
  become caps) on SidebarIconButton, ToolbarIcon and ToolbarImageButton. Measured against Arc on the
  same 1x screen: delay 1.63 s, widths 198/109, height within 1 px; a click dismisses and the next tip waits
  for idle again. Toolbar/header placement uses the same rule but was not compared with Arc's toolbar. Row
  tooltips stay native (URL); Arc shows the title in its own pill there.
- [O static] Arc's tooltip inventory (strings whose translator comment starts "Tooltip"): sidebar "Archive
  this tab", "Close and Keep Pinned", reset pinned tab, mute/unmute tab, camera/mic indicator ("This tab is
  using your camera or microphone"), renameable tab subtitle "Double-click to rename", "Separate from Split
  View", close a tab group, folder create/close ("Close This Folder")/archive, "Clear Today tabs" / "Clear
  unselected Today tabs", "Organize Today Tabs", space header "Edit Space theme" / "Edit Space profile" /
  space options, dock "Drag to Reorder Space", Library button, Site Control Center ("Capture a portion of
  this page", "Capture the full page", copy URL, new Boost, share, ad-blocker states, extension add/pin/unpin),
  PiP (back to tab, close, minimise), Little Arc copy URL/extensions. Short values (< 16 bytes) are inline in
  code, so only their comments are listed.
- Cra (27 Oct): every sidebar/toolbar/Site Control Center/PiP tooltip now uses `.arcTooltip`; tab rows,
  favorites, split rows and URL fields use the cursor anchor and show the title (Arc) instead of the URL;
  the innermost hovered control owns the tip; the Today "Clear" button got "Clear Today tabs".
- Added after that: a muted tab's speaker is a button ("Unmute Tab"); a red dot "This tab is using your
  camera or microphone" from CEF's OnMediaAccessChange (CraBrowser.isCapturingMedia →
  SidebarUIState.capturingTabIDs); the split close button reads "Separate from Split View" while ⌥ is held
  (Arc's allowedModifierKeys / option-click-to-unsplit); "Double-click to rename" as a second line of the
  row tip, once (Arc: WindowData+RenameHints, `renameHintItemID`, `setRenameHint`, `didShowRenameHint`; Cra
  shows it on the first row tip of a tab without a custom name, then sets `didShowRenameHint`). Long
  titles wrap at 280 pt, up to 3 lines (Arc has `maxWidth`, value unknown). Looks of the dot, the mute glyph
  and the two-line tip are Cra's; Arc's weren't observed. Arc shows the speaker for audible tabs too; CEF
  has no audible callback short of an audio handler that takes over playback, so Cra shows it when muted.
  A live Arc sweep (toolbar back/forward/reload, Site Control Center, split menu, favorites, space header,
  folder) failed: a stuck hover-preview card blocked all of Arc's tooltips, so whether those controls show
  a tip in Arc is still open.
- Testing notes: in Arc, still captures taken ~1 s after a pointer move often show the previous hover
  state; record `screencapture -V` instead. AX `AXScroll*ByPage` on Arc's list scrolled the drawing out of
  step with the hit-testing, so later clicks landed on other rows. In Cra, `cliclick c:` is too fast for
  the row's SwiftUI tap; `dd: w:80 du:` selects.

### A pinned tab away from its page (Arc 1.171, 3 Nov 2026, GitHub #139, field metadata + disassembly)
- [O static] `TabCellView` has no reset button. Its fields include `iconContainerView`, `_slashView`,
  `_regionHoverState: RegionHoverState<BackgroundRegion>?` (region `icon | body`, plus modifier flags) and
  `_hoverSubtitleState: HoverSubtitleState?` (`reset | resetAndSeparate`, strings "Back to Pinned URL" and
  "Separate From Pinned Tab"). `TabCellState` carries `canResetTab`, `resetTabTitle`, `resetTabIcon` and
  `resetItemShortcut`, so Arc keeps the pinned page's own name and icon next to the current page's.
- [O static] `ARCUI.SlashView`: a 4 × 15 pt view, stroked from (1, 1) to (w − 1, h − 1) with a 2 pt line and
  round caps, in the `TabCellSlash` asset (black 30 % light, white 30 % dark, P3), with 4 pt after it.
  [O reporter, 2x screenshot] Favicon, 4 pt, the slash, 5 pt, the name (13 pt after the favicon, not 11).
- [I] Hovering the icon region shows "Back to Pinned URL" as the subtitle, and a click there resets the tab.
  Not checked live: which modifier picks `resetAndSeparate`, and whether the icon region gets its own hover fill
  (`_regionalBackgroundView`).
- [O static] `SidebarUI.TabHighlightState`: `developerTab | tabCapturing | syncedTab`, drawn by
  `TabHighlightView` (in `CellSelectionStateView`). It has two 2 pt layers on the bounds inset by 1 pt with a radius
  of 11. For `developerTab` they are systemYellow under black dashes at 80 % opacity, and each dash is the
  perimeter ÷ 60 / 80 / 100 (width < 210 / < 346 / larger). `tabCapturing` is solid yellow, `syncedTab` is
  rgb(0.901, 0.631, 0.827).
- [O static] `TabCellState.subtitle` (built in `TabCellState.init`, first match wins): the host (+ `:port`)
  when developer mode is on for the page; "Double-click to rename" for the rename-hint item; a GitHub live
  folder item's subtitle; else none. `titleSourceInfo` and leaving the pinned URL never set it. Victor's
  "Ahrefs" row shows ahrefs.com because ahrefs.com is in `StorableDeveloperModeState.json`.
- [O reporter, 2x screenshots] Nested rows: Arc's fill starts after the indent (24 pt for depth 1 against 5 pt
  at the top level), so a folder's gutter stays empty.
- Cra (TabRowView): the slash replaces the trailing ↩ button, and the icon region (the fill's edge to just past the
  slash) shows the hover subtitle and resets on click. `TabData.homeTitle` keeps the pinned page's title, and
  going back restores that title and the home's favicon key. The developer ring is `FocusRingLayer(developer:)` on
  the open tab. Each row's fill starts `depth × 18` pt in (23 pt against Arc's 24). The capturing and synced
  rings are not built.

### Closing and pinned tabs, recorded (Arc 1.171, 3 Nov 2026, GitHub #139)
Offline Arc on a fake home (scratch tools: fake-home generator, `sandbox-exec` allowing only loopback, pages on
`pin.lvh.me` / `away.lvh.me` / `dev.lvh.me` port 47139 served locally; `localhost` is developer mode by itself,
so test pages must not use it). Live HID clicks and hovers at 1x, plus a static pass over TabCellState.
- [O live] Close button per row, shown only while the row is hovered (24 pt square, hover square GrayA4,
  radius 6, 6 pt before the fill's right end; glyph two 14 × 2 pt bars, crossed or flat):

  | Row | Glyph | Tooltip | Click |
  |---|---|---|---|
  | Pinned, open | minus | Close and Keep Pinned ⌘W | unloads, back to its pinned page (name and icon too), the tab before it opens |
  | Pinned, background, away from its page | minus | Close and Keep Pinned | back to its pinned page, unloads; selection stays |
  | Pinned, background, on its page (loaded or not) | ✕ | Archive this tab | archived out of the pinned section |
  | Pinned, shown under a closed folder [O static] | minus | Close and Keep Pinned | as above |
  | Today, open | ✕ | Archive this tab ⌘W | archived; the tab below opens |
  | Today, background (loaded or not) | ✕ | Archive this tab | archived |
  | Picked with others | its own button | singular tooltip | acts on that row only |
  | Favorite tile | none | — | ⌘W deselects it, the tab before it opens |
  | Pinned split, open | one minus at the row's end | Close this item ⌘W | the whole split unloads, stays pinned |
  | Pinned split, background | one ✕ at the row's end | Archive this item | the whole split is archived |
  | Today split, open | an ✕ inside every pane | Archive this item | that pane is archived, the split becomes a tab |
  | Today split, background | one ✕ at the row's end | Archive this item | the whole split is archived |

- [O reporter, 2x screenshots, GitHub #243] With the button shown, a long name's ink ends 20.5 pt before the ✕'s
  ink (✕ centred 18 pt from the fill's end), so its box ends ~13.5 pt before the button. At rest the rows look the
  same as Cra's 21 pt tail (not measured). Cra (`TabRowTrailing`): the name's box 15 pt before the first trailing
  control (13 pt from the label's widened box), 21 pt before the row's end with none; it was 26 pt, kept from the
  old trailing ↩ button.
- [O live] ⌘W on several picked tabs closes them all; [O static] a Today tab among them archives every one,
  otherwise they all deselect. The ⌘W keycaps only show on the open row's tooltip.
- [O live] Split cells: 4 pt inside the fill, 4 pt apart, each favicon 6 pt into its cell. An open split draws
  each pane as a 28 pt pill (4 pt inset top and bottom, radius ~6, 224 on the 241 fill, light theme); a hovered
  pinned split shortens its last pill to end 5 pt before the minus.
- [O live] A pinned tab away from its page: current favicon, slash, current title, nothing under it. Its hover
  splits in two: the icon region (a 36 pt rounded square at the fill's left) and the body (the fill from 30 pt
  in to its end). On the icon: the pinned page's favicon (resetTabIcon) replaces the icon, the slash and the close
  button hide, "Back to Pinned URL" shows under the title; with ⌘ held, the current favicon and "Separate From
  Pinned Tab". On the body of a background row: its own fill, the slash hides, the button shows. On the open row
  the icon square darkens over the white fill (241 → 230), left corners round, right edge straight.
  Click on the icon: the tab goes back to its pinned page (a navigation: Back works) and opens. ⌘-click: the
  current page moves to a new Today tab at the top of Today, the pinned tab goes back and stays open.
- [O live] A typed address (⌘L, Enter) on a pinned tab: another host opens a new Today tab (pin.lvh.me →
  away.lvh.me did, so it is the host, not the site), the same host stays in the pinned tab. A same-host link
  stays; another host's link opens Peek, with the peeked page's favicon as a badge on the pinned row.
- [O live] ⌘W on an open Today split archives only the focused pane (the other becomes a tab). ⌘-click picks a
  tab without opening it; the open tab is part of the selection, so ⌘W takes it too.
- [O live] Developer mode: the host and port under the title on every row of that site, the dashed ring only
  on the open one. Nested rows indent 16 pt (favicon 26 → 42, text 45 → 61) and their fill starts after it.
- [O live, 100 fps] The minus makes the row jump to scale 0.9 at once and spring back to 1 in ~0.24 s without
  overshoot (left edge 10 px in at 1x, back by 1.11 s): a critically damped spring, ω ≈ 14 (stiffness 196, damping 28).

### Pressing a sidebar row (Arc 1.172.1, 11 Nov 2026, static: method lists and disassembly)

- [O] Rows: `SidebarBouncyClickCell.performBounceAnimation(isPressedIn:)` on `SelectableCellView` (tabs, splits,
  New Tab, easels). A `CASpringAnimation` on `transform` to scale 0.992 about the centre, damping ratio 0.5,
  response 0.2, held while pressed. Tabs and splits press only on `clickCount == 1`; New Tab on every press.
  Folder and section headers don't press.
- [O] Favorites: `AppTrayItemViewAppKit.isPressed`, the same spring to 0.99 on every press, the whole tile.
- [I] Nothing found springs a row back when a press becomes a drag; Cra does it when the drag starts.
- Cra: CraCore SidebarRowPress, `NSView.springPress`.

### Backdrop-layer blur for light vibrant themes (25 Oct 2026, final)

The system materials could not reproduce Arc's intercept and slope together, so
`ShellView` now blurs light vibrant themes through an untinted `CABackdropLayer`
(`CIGaussianBlur` radius 28) under a black dim layer and a white lift gradient; the
`NSVisualEffectView` path stays for dark themes and as a fallback if the class is missing.
Raw layer response over the same solid backdrops: black 6, white 240 (passes 92 %).
Model: out = a·G + (1−a)·[L·255 + (1−L)(1−D)·blur]. Baked: D 0.23, L 0.21 (top) → 0.18
(bottom), gradient opacity intensity×1.65 (0.42) → ×2.30 (0.58). Measured on the baked
build, five heights, R/G/B:
- white — Arc 204/197/164 · 215/208/167 · 218/201/160 · 219/193/159 · 218/188/154;
  Cra 201/196/165 · 213/202/168 · 219/203/167 · 218/198/161 · 217/193/156.
- black — Arc 123/116/83 · 139/124/90 · 146/129/89 · 154/128/94 · 159/129/95;
  Cra 126/121/90 · 140/129/95 · 149/133/97 · 154/134/97 · 155/131/94.
Every channel within 8 levels, red within 4, at every height over both backdrops.
`CRA_TUNING` keys for the path: `dim`, `lift`, `liftBottom`, `alphaTop`, `alphaBottom`.
- Baked constants after the last fit: dim 0.19, lift 0.16 → 0.18, gradient opacity
  intensity×1.70 (0.43) → ×2.35 (0.59). Measured (c7 run): white 207/202/169 · 217/206/171 ·
  217/201/165 · 218/198/162; black 125/120/87 · 138/127/92 · 143/127/91 · 152/132/96 at
  y = 160/700/1200/1700 (y = 2100 sits under the Dock and is unreliable). Arc re-measured
  over black twice: identical to the level, so the capture noise floor is ≈1.
- Sidebar hidden (⌘S): Arc keeps the rounded card in its 10 pt inset (card edge at 20 px
  after the hide) and puts a sidebar toggle first in the bar, centred 30 pt from the card
  edge, then ← → ↻ at 37 pt pitch. Cra used to go edge to edge; it now keeps the inset and
  shows the toggle. Hide trajectory (card edge, px per 60 fps frame): Arc 568 → 204 → 90 →
  42 → 24 → 20; Cra 568 → 202 → 70 → 32 → 22 → 20 (duration 0.08 s, curve 0.2/0.85/0.25/1).
- Confirmation on the installed build (baked3 run, y = 160/700/1200/1700): white
  203/199/166 · 216/205/170 · 217/201/166 · 220/199/163 vs Arc 204/197/164 · 215/208/167 ·
  218/201/160 · 219/193/159; black 121/117/84 · 137/126/91 · 143/127/92 · 154/133/97 vs
  Arc 123/116/83 · 139/124/90 · 146/129/89 · 154/128/94. Max |Δ| 6, median 2, noise ≈1–2.
- Hide easing refitted to Arc's per-frame progress (66 / 87 / 96 / 99 %): duration 0.085 s,
  curve 0.15/0.7/0.3/1. Two Cra recordings: 568 → 200 → 74 → 36 → 22 → 20 and 568 → 200 →
  74 → 26 → 20; Arc 568 → 204 → 90 → 42 → 24 → 20. Run-to-run spread between the two Cra
  takes (10 px on frame 3) is the keypress phase relative to the 60 Hz capture, so the
  remaining Arc/Cra gap on frames 2–3 (16 / 6–16 px) is at the measurement's resolution.

### Sidebar translucency, re-fitted 25 Oct 2026 (11:30)

The CABackdropLayer path had been calibrated while its blur filter was inert (a CIFilter in
`filters` is ignored for the backdrop capture), so the window behind showed through sharply.
With Core Animation's own gaussianBlur (radius 40) in place, Arc 1.170 (active, Victor theme,
upper sidebar, same screen) measures 184/177/137 over 50 % grey stripes and 213/206/167 over
white: pass-through k ≈ 0.21, ≈158/151/111 over black. Cra with lift 0.35→0.37 and dim 0.36:
185/175/140, 213/203/168, 159/149/114 (k 0.21). Arc's blur also erases a 60 pt stripe pattern
completely; Cra's does too (residual amplitude ≤ 1/255).

### Picture in Picture hover controls (25 Oct)

Victor reports Arc's PiP shows buttons on hover (back to tab, play/pause, close). None of the
captures above could reproduce them: every earlier test window was Little Arc (a URL opened
from outside Arc), and "Extensions ▸ Picture in Picture" is Google's Picture-in-Picture
extension, not Arc's own feature. A regular Arc tab playing audible video (−60 dB tone) and
then left with ⌃Tab did not open Arc's auto PiP on this Mac either, so the setting is likely
off here; it is not stored in any readable file (Arc's Storable*.json, Chromium Preferences or
defaults). [U] Arc's control layout and styling.

Cra's controls, built from Arc's control inventory (strings above): close (top-left, "closes
the pip window"), back to tab (top-right, "returns to the original tab", `pip.exit`), play/pause
centred between "Skip back 15 seconds" / "Skip ahead 15 seconds". White SF Symbols, translucent
disc on hover (white 20 %, 32 % pressed), a black scrim (45 % at the edges, 15 % in the middle)
that fades in over 0.15 s when the pointer enters and out over 0.25 s when it leaves or rests for
2.5 s. Verified in a scratch Cra: controls appear on hover, pause stops the video (frame counter
froze 5 frames after the click), back to tab brings the source window up and returns the video.
Captures: build/pip-verification/cra_ctrl_*.png. To be calibrated against a capture of Arc's
hovered PiP.
- Inactive window (25 Oct, 12:10): Arc drops the backdrop and shows a flat 149/143/104 regardless
  of what is behind. Cra used to switch to a 0.75 white lift (244/234/199 over white, 211/201/166
  over black), which made the sidebar flip between dark-translucent and pale on every app switch.
  Now dim 1.0 + lift 0.28 while inactive: 149/139/104 over both white and black.

## Dia import onboarding (Dia 1.54.2, 25 Oct 2026)

Source of Cra's import window (Sources/Cra/UI/Onboarding). Evidence: strings and Swift reflection
metadata (`__swift5_fieldmd`) of `Dia.app/Contents/MacOS/Dia`, asset catalogs read with
`Bundle.image(forResource:)` / `NSColor(named:bundle:)`, and window captures of Dia's own flow
opened from Dia ▸ Import from Another Browser… (stopped before "Begin Importing", nothing imported).

- [O] Views (module `Onboarding`): `ImportView`/`ImportContentView` hosts `ImportSelectionView`
  (collection of `ImportBrowserItemView`: icon, label, radio button, spinner, "N of M spaces"
  profiles button), `ImportProfilesView` (space/profile checkboxes), `ArcPreviewContentView`
  (`SpaceCheckboxView` rows + `DiaSidebarPreviewView`: favourites cells, header label, tab-group
  rows), `ImportProfilePickerView` ("Unlock your data for import", keychain), `ImportProgressView`
  (`CategoryItemView` tiles, paced by `ImportProgressController.progressUIIntervals`) and
  `ExtensionsView` (`BrowserExtensionCheckBox`: icon, name, checkbox, install spinner;
  `ExtensionsController` installs from the Web Store and tracks installed/failed IDs).
- [O] Copy: "Import now to get connected" / "Import once and stay in your flow. Your apps, tabs,
  passwords, bookmarks and extensions come with you."; "Select spaces to import" / "We'll import
  your Arc spaces, tabs, and folders to Dia."; "Customize which spaces to bring over to Dia";
  "Import your extensions" / "Pick your essentials. You can always add more extensions later as
  you settle in with Dia."; "Importing from %@" / "Hold on while we fetch your data"; "Some import
  steps failed:", "%@ import failed".
- [O] Geometry (dark, 2x captures, AX frames): window 928×544, no title bar, close ✕ 26×22 at
  (887,16). Left column x 32, width 440: serif title (Exposure-550) top 56, cap height 20.5,
  713 px wide; subtitle 15 pt SF, line pitch 21.5, top 104; browser cards 215×80 in a grid at
  y 174 with 10 pt gaps, no fill, hairline #5E5E5E (selected #9D9D9D), corner ≈22–24 continuous,
  logo 52×52 at (19,14), label 16 pt at x 82, radio 24 pt (ring 1.5 pt #505050; selected white
  ring + 17.5 pt disc) centred at x 173.5. Primary button 442×42 at y 470, #E0E0E0, 13 pt
  semibold black with a return glyph, disabled text #7F7F7F on the same fill. Secondary + primary
  pair: 146 + 290 pt, 6 pt apart. Art panel (painted `Rebrand*Screenshot`) from x 451, its left
  edge feathered with spray noise.
- [O] Colours (light / dark): ButtonPrimaryBackground black .85 / white .85; ButtonDefaultBackground
  .08 / .08; RebrandAppTitleText .85; RebrandBodyText .55; RebrandRowBackground black .015 / white
  .08; RebrandRowBorder .08 / .16; ImportSelectionCaption .3 / .4; ImportProgressItemBorder .1;
  LoadingSubtitle .3 / .4; Background white / black.
- [O] Extensions in Arc and Dia: `User Data/<profile>/Secure Preferences` → extensions.settings;
  location 1 (Web Store) manifests keep `key`, so a copy loaded with --load-extension keeps its ID.
  Cra copies the version folder to `<data dir>/Extensions/<id>` (location 8 in Cra's prefs);
  verified: 21 of Arc's extensions load with Arc's IDs. [U] Extension storage (Local Extension
  Settings) is not copied, so sign-ins inside extensions start fresh.
- [O] Since GitHub #203 a copy of a Web Store extension (the store's `update_url`, folder named
  after the ID its `key` gives) becomes the store's own install in each profile it loads in, as
  Dia's `ExtensionsController` installs from the store: the first page a profile loads sends
  `Cra.installFromWebStore` (scripts/cef-patches/freezing-vote.patch, WebstoreInstaller, the
  signed CRX), which lands as location 1 with `from_webstore`; the copy then stops loading there
  and is deleted once no profile loads it. The store's version may not ask for more permissions
  than the copy. Before, a copy that reloaded itself (`chrome.runtime.reload()`) came back as
  location 4 (UNPACKED), which Chromium turns off without developer mode
  (DISABLE_UNSUPPORTED_DEVELOPER_EXTENSION, 1 << 24), and the reason stuck after the next launch
  loaded it as location 8 again; extension-reload-location.patch keeps such a reload at location
  8 and clears that reason.
- Not reproduced: the Arc space step and the extensions step were not opened in Dia (the menu flow
  goes browser → "Unlock your data" → import; the space and extension steps belong to first-run
  onboarding), so their layout follows the reflection metadata and the measured browser step.
  Exposure and Dia's paintings are not shipped; Cra uses New York and draws its own art (badge
  ring after `RebrandImportScreenshot`, window mock after `RebrandArcImportPreviewScreenshot`).

## Default browser (Arc menu, Dia 1.54.2 onboarding, 25 Oct 2026)

Source of `SystemIntegration`, the onboarding's `.defaultBrowser` step and Settings ▸ General.
Static only: strings and `__swift5_fieldmd` of `Dia.app/Contents/MacOS/Dia`, art from
`BoostBrowser_Unboxing.bundle` (`Bundle.image(forResource:)`); Dia's onboarding was not re-run.
- [O] Arc app menu (user screenshot): Settings… ⌘, / Share Arc / Set as Default Browser with ⌘♡
  as its key equivalent (no key types ♡), then a separator before Import from Another Browser….
- [O] Dia's onboarding `Flow` enums list `newDefaultBrowser` ahead of `disclosure`, `import` and
  `importProgress`; Cra shows the step first on a fresh install, before the import.
- [O] `NewDefaultBrowserContentView`: two-line title "Fast, secure, and packed with all your browser
  essentials", rows `setAsDefaultRow`, `addToDockRow`, `launchAtLoginRow` (plus a trial checkbox
  Cra drops), each a `DefaultBrowserCheckboxRow` (checkBox over `rebrandBackgroundView`), and a
  button bar. Copy: "Set Dia as default browser" / "Open links and web pages in Dia by default";
  "Add Dia to Dock" / "Quick access to Dia whenever you need it"; "Open Dia at login" /
  "Automatically open Dia when you sign in".
- [O] `NewDefaultBrowserController` uses DefaultBrowserClient, DockClient (`getDockData`,
  `writeDockData`, `addCurrentApp`, order `beforeDefaultBrowser` / `afterDefaultBrowser`) and
  LaunchAtLoginClient; `Options` = defaultBrowser, addToDock, launchAtLogin; `isShowingPrompt`
  while the system dialog is up. Cra inserts its Dock tile after the current default browser's.
- [O] Art `RebrandDefaultBrowserScreenshot` (476×544 pt): the app tile (144 pt) raised out of a
  glass Dock strip (y 205–372) between two blank tiles (106 pt), running dot at (266, 338), on a
  warm painting. Cra draws it with its own icon and shows the current default browser as the
  left neighbour.
- [U] Which checkboxes Dia ticks by default, its skip button title and which Dock order it uses.
  Cra ticks default browser and Dock, leaves login off, and labels the secondary button Skip.

## Dia onboarding steps and multi-browser import (Dia 1.54.2, 25 Oct 2026)

Source of the full first-run flow (`ImportFlow`, `OnboardingSteps`) and the importers
(`BrowserSources`, `ChromiumImporter`, `FirefoxImporter`, `SafariImporter`, `CredentialImport`).
Static evidence: `__swift5_fieldmd`/`__swift5_reflstr` of `Dia.app/Contents/MacOS/Dia` (parser in
scratch `fieldmd.py`), its localization strings, and the SQLite/Keychain layout of installed
browsers on this Mac read read-only. Dia's onboarding itself was not re-run past the browser step.

- [O] Dia's onboarding `Flow` order: `newDefaultBrowser, connectedApps, atlassianFirstParty,
  disclosure, import, importProgress, importPasswordsAndCookiesResult, pinnedTabs, personalization,
  safariExportedData, extensions, outro` (`OnboardingStepName` adds welcome/auth/account). Cra runs:
  cover → default browser → privacy (disclosure) → import (source → Safari export / unlock → spaces →
  extensions → progress → passwords result) → pinned tabs → personalization → outro. Cra drops Dia's
  AI-tied steps (connected apps, Atlassian, ChatGPT memory opt-in, the "try for a week" trial).
- [O] Cover (`Auth flow cover page`): wordmark, one-line pitch, "Get Started" + "Sign In". Cra uses
  its own site tagline ("A calmer way to browse").
- [O] Privacy (`DisclosureView` / `DisclosureContentView`: `adBlockerRow`, `shareDataRow`): title
  "Privacy in Dia, you're in control"; "Block third-party ads and trackers" / "You won't see them.
  And they won't see you." Cra keeps the ad-blocker row (see "Third-party ad and tracker blocking")
  and drops Dia's share-usage-data row.
- [O] Unlock (`ImportProfilePickerView`): "Unlock your data for import" / "Some data is encrypted, so
  macOS will ask for your computer password …" with a per-profile picker when a browser has several.
  Result screen (`ImportPasswordsAndCookiesResultView`): success "Your passwords and cookies are now
  available …"; failure "Something went wrong" with Try Again / Skip.
- [O] Safari export (`SafariExportedDataView`): "Import from Safari", numbered steps (File ▸ Export
  Browsing Data to File), and a "Choose .zip file or drag it here" drop well; validator messages
  ("Please select a folder or zip file.", "The folder is missing required files …"). Cra reuses the
  drop well for Firefox's exported passwords CSV.
- [O] Pinned tabs (`PinnedTabsView` / `PinnedTabButton`): "Keep your favorites handy" / "Pin important
  apps …", a grid of preset apps (`PinnedTabs/Icons/*`: Gmail, Calendar, Slack, Notion, GitHub,
  Figma, YouTube, Spotify, Drive, Docs, Linear, Canva…) seeded from `rankedTopSitesTask`. Cra fills it
  from the imported browser's most-visited hosts (History/places.sqlite) plus the presets, with
  favicons from the source's Favicons DB.
- [O] Personalization (`PersonalizationView`): "Pick the theme color and layout that feel right for
  you.", colour swatches + a tab-layout picker ("Classic"/qualifier). Cra maps the swatches to
  `SpaceTheme.presets` and the layout to the toolbar setting.
- [O] Outro (`RebrandOutroView`): "Welcome to your new home on the internet" (older build: "Welcome
  to a better work day"), animated logo honouring Reduce Motion.
- [O] Importers. Chromium family (Chrome, Brave, Edge, Opera, Opera GX, Vivaldi, Chromium, and Arc's
  and Dia's own Chromium profiles): profiles from `User Data` (+ `Local State` info_cache), bookmarks
  from `Bookmarks`, open tabs from the SNSS `Sessions/Session_*` (command stream, versions 1 and 3;
  2/4 are encrypted), top sites from `History`, favicons from `Favicons`. Firefox/Zen: `profiles.ini`
  → profile, `places.sqlite` bookmarks + frecency top sites, `favicons.sqlite`, session from the
  `sessionstore*.jsonlz4` (mozLz4 = "mozLz40\0" + u32 size + LZ4 raw). Safari: only what it exports.
- [O] Passwords and cookies (`CredentialImport`). macOS Chromium v10 blobs = AES-128-CBC, key =
  PBKDF2-SHA1(secret, "saltysalt", 1003, 16), IV = 16×0x20; the secret is the login-Keychain item
  "<Name> Safe Storage" (one OS password prompt per browser). Cookies DB version ≥ 24 prefixes the
  plaintext with SHA-256(host_key) — checked to confirm the key, and re-added for Cra's own profile.
  Cra re-encrypts every row with its own key (the secret in Cra's "Cra Safe Storage" item,
  `SafeStorage.swift`) and stages them to `pending-credentials.json` (0600); `main.swift` writes them into
  the profile's `Cookies` / `Login Data` before CEF starts (both are locked while Chromium runs) and
  only when no other instance is up, then deletes the file. Verified end-to-end against this Mac's Dia
  profile (1 login + 3052 cookies decrypted, staged, applied on relaunch, idempotent on re-run).
- [O] Cra's own Safe Storage (reported by Rainatsu, 27 Oct 2026). Until then Cra ran Chromium with
  `--use-mock-keychain`, so its profile's v10 values used the public secret "mock_password", and imports
  moved Keychain-protected data under it. Now Chromium reads "Cra Safe Storage" (account "Chromium"):
  `scripts/cef-patches/keychain-service-name.patch`, and for the cef-156.0.14-codecs2 framework a
  binary patch in `fetch-cef.sh`. The compiler folded the name's length (21) into both places that copy it
  into a `std::string` (`mov wN, #0x15` at 0x215fe50 / 0x215ff8c), and builds the 8-byte account
  "Chromium" from `movk` immediates. Padding a shorter name with NULs is therefore not enough: the
  lengths must be patched too, and the account cannot be renamed that way. Before Chromium starts, a
  signed Cra creates the item (16 random bytes, base64, as Chromium does) and, the first time, re-encrypts
  every mock-keychain BLOB in each profile's Cookies / Login Data / Web Data databases and the staged
  import. Unsigned dev builds stay on the mock keychain for profiles that never used the Keychain.
  `Sessions_Encrypted` is not migrated (Cra does not use Chromium's session restore).
- [U] Dia's exact top-sites ranking, its default checkbox states, and the encrypted SNSS v2/v4 session
  format. Firefox saved logins are not read from `logins.json`/`key4.db`; Cra takes Firefox passwords
  only via its own exported CSV, like Safari.

## Dia nav-bar status (Dia 1.54.2, 25 Oct 2026)

Static only (strings of `Dia.app/Contents/MacOS/Dia`, no decompiler; not observed at runtime).
- Dia confirms browser actions inside the navigation bar instead of a toast: the status view
  (`NavigationBar.AssistantBarStatusView`) takes the title/URL slot, e.g. "🔗 Copied Current URL"
  (user screenshot). Localisation comments call these "Nav-bar status" and ship Title Case and
  sentence case variants.
- Messages found: Copied Current URL, Copied URL as Markdown / URLs as Markdown, Copied to
  clipboard (link), copied (clean, tracker-free) URL(s), Copied login code, Cannot Add New Pane
  (split limit; `rectangle.portrait.split.2x1.slash` sits next to the view), extension installed,
  password saved, import progress/result, '<shortcut> again to <action>', trace status.
- Unknown: display duration and transition (no runtime capture). Cra shows the status for 2 s
  with a 0.15 s fade in / 0.2 s fade out (`SidebarUIState.flashStatus`). Replaced 2 Nov 2026: Arc shows these
  ("Copied Current URL", "Cannot Add New Pane") as its toast, one component for every confirmation, and Cra now
  does too (`ShinyToast`, see the #85 section).

## Dia Extensions menu (Dia 1.54.2, 25 Oct 2026)

[O] Menu bar order: Dia, File, Edit, View, Tabs, Bookmarks, History, Extensions, Window, Help (AX of
the running app). Extensions lists one item per installed extension with its 16 pt icon, in plain
ordinal order ("dataslayer" after "Vercel"), then a separator, "+ Add Extension…", "Manage
Extensions…", "Pin Extensions…" (strings "A menu item to add a browser extension" / "manage browser
extensions" / "pin extensions"; capture of the open menu). Items run the extension's action
(`BrowserExtensionActionsProxy.executeAction`). [U] What Add Extension… opens and the layout of the
pin UI. Cra: UI/ExtensionsMenu.swift. An item runs the extension's action on the current tab
(MainWindowController.runExtensionAction: Extensions.triggerAction over the DevTools pipe, Chrome's
real popup with activeTab); without the pipe it opens the popup page in a Little Window, else the
options page. Pin Extensions… is a checklist submenu backed by `ExtensionStore.pinnedIDs`.

## Toolbar extensions and Split View button (Arc 1.170, 25 Oct 2026)

- [O] Arc's content toolbar ends with the pinned extensions, an Extensions button and a Split View
  button (user screenshot: 1Password, Detailed SEO "D", sliders-in-a-square, split square).
  Pinned = Chromium's own `extensions.pinned_extensions` pref in Arc's profile
  (`aeblfdk…` 1Password, `pfjdepj…` Detailed SEO). Binary strings: `contentToolbarOpenExtensionsButton`,
  `extensionsMenu`, `didDismissExtensionsMenu`, "Open pinned extensions picker.", "Manage Extensions",
  `pinExtension:` / `unpinExtension:`; the Extensions button opens a menu, not a web popover.
- Cra: `ContentToolbarView.trailingButtons` (pinned icons from `ExtensionStore.pinnedIDs`, the menu
  bar's Extensions menu under the button, Split View → addSplitView).
- Running an action (CEF 154 has no extension API): `Extensions.triggerAction` over a private
  `--remote-debugging-pipe` (fd 3/4 held by Cra, `--enable-unsafe-extension-debugging`; CEF's own
  per-browser DevTools client gets "Method not allowed"). It needs the *tab* target (page →
  tab via `Target.attachToTarget` + `setAutoAttach` on each tab target) and a Chrome toolbar:
  with `CEF_CTT_NONE` Chromium segfaults (null extensions container), so page windows get
  `CEF_CTT_NORMAL` with the toolbar view hidden (`CRA_NO_CHROME_TOOLBAR=1` opts out). Chrome's
  real popup appears (activeTab granted; Detailed SEO analysed the page) anchored to the hidden
  toolbar; `ExtensionActions` moves it under Cra's button and keeps it there on resize.

## Third-party ad and tracker blocking (Dia onboarding privacy step, 25 Oct 2026)

Dia's onboarding checkbox "Block third-party ads and trackers" ("You won't see them. And they
won't see you.") maps to `AppSettings.blockAdsAndTrackers` (default on; Settings > Privacy).
`CraClient::GetResourceRequestHandler` attaches a `CefResourceRequestHandler` whose
`OnBeforeResourceLoad` returns `RV_CANCEL` when the request host, or a parent domain of it, is on
the bundled list and the request is third-party to the tab's top-level page (the page is not on the
listed domain and the two hosts are not the same site, eTLD+1 approximated without the PSL).
Main-frame navigations and downloads always load; subframes (ad iframes) can be blocked. Every Cra
tab, popup and Little Window, Alloy or Chrome-style, uses `CraClient`; DevTools does not. Matching
lives in `Sources/CraCEF/CraContentBlocker.h` (lock-free: an immutable set behind an atomic
pointer, plus an atomic switch), the API is `+[CraCEFRuntime setContentBlockingEnabled:]`,
`setBlockedDomains:`, `loadBlockedDomainsFromFile:completion:`, `shouldBlockRequestURL:onPageURL:`.

The list is `resources/blocklist/domains.txt` (22,510 domains, copied into
`Contents/Resources/blocklist` by `scripts/build.sh` and `scripts/dev.sh`), fetched 2026-10-25 and
merged from:

- AdAway default blocklist, https://github.com/AdAway/adaway.github.io (hosts.txt), CC BY 3.0.
- Anudeep's Blacklist, https://github.com/anudeepND/blacklist (adservers.txt), MIT.

Both allow redistribution in an MIT app with attribution, which is in
`resources/blocklist/NOTICE.txt`. Rejected: EasyList/EasyPrivacy (GPL-3.0 / CC BY-SA), DuckDuckGo
Tracker Radar (non-commercial), hagezi (GPL-3.0), Disconnect (GPL-3.0), StevenBlack unified hosts
(MIT itself but includes non-commercial sources such as MVPS). Domain lists can't catch first-party
ads served from a site's own hosts (YouTube video ads, Facebook/Instagram feed ads, sponsored
search results) or cosmetic ad slots; requests from service workers and extension background pages
(no browser) are not filtered.

## Dia space paging and window buttons (Dia 1.54.2, 25 Oct 2026, static only)
[O] = read from the binary, [I] = inferred, not observed running.
- [O] Swift field metadata: `ARCUI.PageSwipeController` (pages with widths, `pageOrigins`,
  `trackingState {isTracking, isAnimating}`, `scrollingShouldBeginHandler(NSEvent)`, `positionUpdateHandler`,
  `PagingPosition {floorPageID, ceilPageID, progress}`, `performsPageDetentHaptics`, `lastDetentPageID`,
  `NonGesturalScrollState {cumulativeDistance, lastEventTime, lastTriggerTime}` for wheels).
  Settling is `SettlingAnimation {fromPosition, targetPosition, positions, keyTimes, duration}` run as a Core
  Animation keyframe animation (`TabSidebar.PagingContainerViewController.CoreAnimationSettling`, `CADisplayLink`).
  `ARCUI.VelocityTracker {value, pastValues}` measures release speed.
- [O] `TabSidebar.PagingContainerViewController`: one `NSViewController` page per space in a horizontal
  `pagingContentView`, loaded lazily (`loadedPages`, `isPageCleanupScheduled`). `SpaceModels.SpacePagingTransition
  {fromSpaceID, toSpaceID, progress}` drives the window tint (`SpacePagingTintSettlingAnimation` keyframes colours).
  `PendingRubberBandSnapBack`/`RubberBandDragState` exist for the edges.
- [O] No `trackSwipeEvent` use: Dia reads raw scroll events. It imports `SwiftUI.Spring(duration:bounce:)` and
  `Spring.update(value:velocity:target:deltaTime:)`; the one sampler found passes `bounce: 0`, but its callers are
  physics code (atan2, pendulum), so the paging spring's own duration was not recovered.
- [I] Cra copies the structure: `SidebarRootView` pages every space side by side, `MainWindowController` locks the
  axis after 6 pt, tracks 1:1 with a 0.5 x rubber band past the ends, ticks `.alignment` haptics per page, and
  settles with `interpolatingSpring(duration: 0.4, bounce: 0, initialVelocity:)` seeded from the last 80 ms of
  deltas (flick > 0.8 pages/s or past half a page changes space). `PagedSpaceBackground` mixes the two spaces'
  gradients by progress. 0.4 s is a design choice, not a Dia measurement.
- [O] Window buttons: Dia's `Window.PlatformWindow` overrides only key/main bookkeeping, `styleMask` (pass-through)
  and `_usesCustomDrawing` (returns NO); no active-appearance override. Cra keeps its buttons coloured while
  inactive by overriding AppKit's private `_hasActiveAppearanceForStandardWindowButton:` (checked on a test window).

## Arc Settings window (Arc 1.172.2 build 90755, 11 and 12 Nov 2026)

First measurement of Arc's own Settings window (GitHub #372); until then Cra's was Dia's (next section). Arc ▸ Settings… opened
through the menu with Accessibility, tabs switched with `AXPress`, 1728 × 1117 pt display, dark and light. Frames, strings and
fonts from the accessibility tree (fonts through `AXAttributedStringForRange`), window captures with `screencapture -l` (size
checked: 2736 × 2600 px for 684 × 650 pt), colours from the PNG's raw bytes (Display P3), motion from ScreenCaptureKit
recordings of Arc's windows other than the browser window. No page content was captured. Keys and behaviour of the rows come
from the binary (static strings, metadata and its key table; nothing run), marked [binary].

- [O] The window is **684 × 650 pt, fixed**: zoom and minimise are off, no tab resizes it. It opens at x 522, y 119 (centred across, near
  the top) and **always on the first tab**, not the one used last (closed on Shortcuts, reopened on the first). The title bar shows the
  tab's name, centred and dimmed; traffic lights are 16 pt at x 8, 31, 54, y 8. [binary] The frame autosave name is
  `company.browser.Settings.FrameAutosaveName`, the panes (`ArcPreferencePane`) are account, general, max, profiles, keyBindings,
  links, advanced, staff, appIcon.
- [O] **Tabs**, in a toolbar 56 pt tall (y 32–88): a glyph over the name, buttons 55 pt wide (Shortcuts 63, Advanced 64, labels 12 pt)
  with 1 pt gaps, the group (464 pt) centred. In order: Account (named after the user), General, Profiles, Max, Links, Shortcuts, Icon,
  Advanced. The chosen tab is a pill 55 × 47 with a 7 pt corner and its glyph and name in the system blue: `(38, 37, 65)` with a
  hairline in dark, white with a soft shadow in light. A hairline under the toolbar. [binary] Glyphs: Account
  `person.crop.square.filled.and.at.rectangle` (18 pt medium), Profiles `person`, Shortcuts `keyboard`, Advanced
  `slider.horizontal.3`, General and Links are bundled 24 × 24 template PDFs.
- [O] The body is 562 pt tall (y 88–650) and scrolls (Max, Links, Icon, Advanced do); the Shortcuts list and the Icon list scroll inside
  it. Side margin 64 pt, first card 20 pt below the toolbar, cards 556 pt wide, a 1 pt border, corner ≈ 5.5 pt (buttons 5.75, the window
  ≈ 15; fitted to the corner pixels), 10 pt inside a row, hairlines between rows, 9 pt between cards. Switches 36 × 16 pt, 10 pt from the
  card's edge; buttons 24 pt tall. Rows with a switch are 36 pt (pitch 37), with a 24 pt control 44. Text is the system font: 13 pt for
  rows and body, 11 pt for sub-text and counts, 12 pt for a shortcut's description, 14 pt semibold for a shortcut's name and the icons'
  names, 11 pt semibold "CURRENT ICON".
- [O] Colours (raw P3 bytes, dark / light): window and toolbar `(31, 30, 53)` / `(255, 255, 255)`; the hairline under the tabs
  `(35, 35, 35)` / `(230, 230, 230)`; card `(34, 33, 56)` / `(251, 251, 251)`; card border and separators `(56, 55, 76)` /
  `(226, 226, 226)`; buttons `(45, 44, 66)` / `(239, 239, 239)`; pop-ups `(48, 47, 67)` / `(236, 236, 236)`; switch on `(17, 125, 253)` /
  `(0, 118, 245)`; a chosen profile row `(32, 38, 67)` / `(237, 244, 255)`; Max banner `(51, 60, 255)` in both; Links picture
  `(222, 126, 133)` / `(255, 161, 164)`. The window follows the system appearance.
- [O] Motion: opening is the standard AppKit scale-in (first frame already 98.8 % of the size, full after 5 frames ≈ 100 ms, opacity
  steady), closing 3 frames (scale to ≈ 89 %, opacity 89 → 44 → 10 → 4 %); **a tab switch is instant** (one frame changes, no fade,
  no resize); a sheet opens in ≈ 240 ms with the window behind it darkening and closes in ≈ 210 ms. Cra's window has the same
  opening, closing and instant switch.
- [O] **General**: "Automatically update my Arc" ⓘ, "Warn before quitting" (card), "Previews" with Previews Settings… and "Manage your
  default search engine, Auto-Archive, and downloads in Profile Settings." with Profile Settings… (card). Previews Settings… is a 422 pt
  sheet "Show Arc Previews:" with seven checkboxes: Arc Folders, Google Calendar, Google Mail, Outlook Calendar, Outlook Mail, Recent
  pages on Linear, Notion, and Figma, Notion Calendar. [binary] keys `folderPreviewEnabled`, `calendarPreviewEnabled`,
  `gmailPreviewEnabled`, `outlookCalendarPreviewEnabled`, `outlookEmailPreviewEnabled`, `recentPagesPreviewEnabled`, `cronPreviewEnabled`
  (Notion Calendar). Recent pages read the local history of notion.so, linear.app, figma.com and atlassian.net/wiki (no API);
  Notion Calendar shows Google Calendar's preview on calendar.notion.so; Outlook is OAuth with Microsoft Graph (GitHub #376).
  Arc 1.172.2's main binary, recent pages: `Previews/RecentPagesFetcher.swift` `search(domain:tidyTitleConfiguration:browserContextID:)`
  (per profile, titles through Tidy Tab Titles), left out: `notion.so/samlauthcallback`, `…/externalintegrationauthcallback`,
  `…/googlepopupcallback`, `…/oauth2callback`, `figma.com/files/recent`. Empty lines "Recent Linear projects and issues appear
  here.", "Recent Notion docs appear here.", "Recent Figma files appear here.", "Recent Confluence pages appear here."; the ＋ opens
  linear.app/new, notion.so/new, figma.com/new, confluence.new. The card itself wasn't seen (no accounts); Cra's (CraCore
  RecentPagesPreview) lists favicon, title and age in the Gmail card's style, on favorites and pinned tabs.
  Notion Calendar has no fetcher of its own in the binary (only `calendar.notion.so`/`.com` and `…/event/create`): its card is
  the Google Calendar preview. Outlook's empty mail line shares Gmail's string. Cra reads Outlook without Arc's Graph sign-in:
  CraCore OutlookPreview borrows the sign-in headers of a hidden Outlook page's own `/owa/service.svc` requests (FindItem,
  GetCalendarView).
- [O] **Profiles**: a line on profiles, a list on the left ("Your Profiles", "Default — 5 Spaces", + − and rename under it, 205 pt wide)
  and the chosen profile's cards on the right: Search engine, Manage search (Search Settings…), Include search engine suggestions ·
  Archive tabs after (12 hours (default), 24 hours, 7 days, 30 days), New documents (——, Confluence Page, Google Doc, Notion Page, Word
  Doc), Download location (Downloads, Other…, Ask every time) · "Your Data and Settings": Privacy and Security, Passwords, Credit Cards,
  Notifications, Clear Browsing Data (24 pt coloured tiles, arrows). [binary] New documents is `defaultNoteDocumentApp`, a per-profile
  map, and feeds the command bar's "New Google Doc" and the like (`doc.new`, `app.notion.com/new`, `word.new`, `make.page`; GitHub #375).
- [O] **Max**: a banner (blue, the word and flowers, a wavy bottom edge), "Let Arc do more for you with Max…", a card "Enable Max" with
  a button and "Automatically enable future Arc Max features", then a card of six rows with a picture each (Tidy Tabs, Instant Links,
  5-Second Previews, Tidy Tab Titles, Tidy Downloads, ChatGPT in the Command Bar) and "Max features require that we send data to
  our AI partners.". [binary] The button has no key of its own: it reads Turn Off Max with every feature on, Turn On All with some,
  Turn On Max with none, and a press sets them all; the per-feature keys are `tidyTabsEnabled`, `instantLinksEnabled`,
  `hoverCardsEnabled`, `renamePinnedTabsEnabled`, `renameDownloadsEnabled`, `gptSiteSearchEnabled`, and the auto switch is
  `arcMaxAutoOptInEnabled`.
- [O] **Links**: a 684 × 135 picture (a Little Arc, rose, wavy bottom edge), "Little Arc is a smaller, simpler Arc window…", a card of
  "Open Little Arc when I press ⌥⌘N in any app", "Open Little Arc when clicking on links with ⌥⌘ held", "Links from other apps open in
  Little Arc" and "Archive Little Arcs after:", a rule, "Peek is a way to preview a link…", a card of the two Peek switches (the second
  with the note "This only affects Favorites and Pinned tabs"), a rule, and a card "Choose where links open inside Arc." ⓘ with Air Traffic
  Control…. [binary] the ⌥⌘ switch is `optionCommandClickLittleArcEntryPointEnabled`; the click itself isn't measured (GitHub #373).
- [O] **Shortcuts**: "Start with the basics" and a button "Learn the Essential Shortcuts", a card with a field ("Type a feature name or
  shortcut (like “Command E”)", which also finds by keys: "command e" → Open Extensions) over one flat list "Default Shortcuts" by name
  (110 rows here, rows 48 pt, the keys on white 64 × 24 caps, `---` for none), and on the right two 64 pt key caps, "Custom Shortcuts"
  or the chosen action's name and description, "Reset Shortcut to Default" and a "…" menu (Remove Shortcut, Reset All Shortcuts,
  Extension Shortcuts…). An action that has a shortcut also has a pop-up Prefer Websites / Use Both / Prefer Arc ("When shortcuts
  conflict, Arc wins.") [binary] `priority` = `low` / `promptAfterConsumedByWebView` / `overrideWebView` (GitHub #374).
- [O] **Icon**: a radio list of the alternate icons (64 pt picture, 14 pt name, "CURRENT ICON" under the chosen one, rows 81 pt): The
  Original Arc, Candy Arc by Dmitry Novikov, Hologram, Neon, Fluted Glass, Schoolbook, Colorful. [binary] They unlock by inviting
  friends ("Refer %d friend(s) to unlock"); a remote flag opens them all.
- [O] **Advanced**: three cards of switches on 20 pt coloured tiles — "Play Arc sound effects", "Haptic feedback when reordering tabs" ·
  "When opening Arc, restore windows from previous session", "Allow window dragging from the top of webpages", "Show full URL when
  Toolbar is enabled", "Enable Shared Quotes when highlighting text." · "Enable Picture in Picture when you leave a video tab", "Allow
  websites to get your theme data", "Enable Boosts on websites you visit" — then More Settings… (`arc://settings`), Reset Translated-site
  Prompts (`resetTranslateSettings`) and Export Data (a Markdown file of every Space and tab, "Arc Data Export.md").
- [O] **Account**: the user's card, "Account" with the email, "Sync Sidebar", "Gift Arc to a Friend". Cra has no account; its sync is the
  first tab.
- Cra's window is Arc's since GitHub #372; Tabs, Privacy, Extensions, Plugins and Performance, which Arc has no tab for, are Cra's own:
  Privacy and Extensions after Advanced, the rest inside General, Extensions and Advanced.

## Dia Settings window (Dia 1.54.2, 25 Oct 2026)

Evidence: window-id captures (`screencapture -l`) and the accessibility tree of Dia's own
Settings window (Dia ▸ Settings…, driven through AX: `AXSelected` on sidebar rows, `AXPress`
on the close button; synthetic clicks from cliclick did not reach the window), plus strings
and class names of `Dia.app/Contents/MacOS/Dia` (`Preferences.*`, `BoostBrowser_Preferences`).
Dark mode only; light mode was not observed.

- [O] Window `preferencesWindow`: 778×509, close button only (zoom/minimise disabled), hidden
  title, an `NSSplitViewController` (AXSplitGroup, splitter at 204, not draggable) whose sidebar
  is full height, and a unified toolbar (AXToolbar 52 pt) holding Back/Forward (41×52 each,
  drawn as one 69×38 capsule, black ≈25%, at x 214) and the pane title (15 pt bold, x 293).
  Traffic lights at (18,18). Window colour 61/57/54, sidebar 46/43/41 (wallpaper-tinted
  standard materials), a 1 pt lighter line (78/73/68) on the split.
- [O] Sidebar rows: Account, Tabs, Privacy, Profiles, Skills, Apps, Shortcuts, Advanced. Rows
  196×28 inset 8, first row 64 from the top, 20×20 glyph at +20, 13 pt label at +49. Glyphs are
  SF Symbols (person.text.rectangle, square.on.square, hand.raised, person, keyboard,
  gearshape.2; Skills and Apps are custom). Selected row: accent fill (1/158/255) + white text
  while key; grey fill (white ≈10%) + accent-coloured label when not key. Corner ≈6.
- [O] Card panes (Account, Privacy, Profiles, Apps): 13 pt semibold header 8 in from the card,
  cards 21 from the content edges, 20 below the toolbar, radius 12, fill white ≈7% (75/73/69),
  rows 43 tall (49 with push buttons), 10 pt insets, row dividers white ≈12% inset 10, 11 pt
  secondary footnote 5 below. Privacy: "Content blocking" → Block ads / Block cookie banners /
  Block trackers (NSSwitch 46×22, 20 pt coloured rounded-square glyphs: red hand, orange
  cookie, yellow glasses), "Advanced Settings" button 7.5 under the card; "Data" → "Share content
  data to help improve Dia" (off) + "This data will not be tied to your profile".
  Account: Name / Email (value secondary, "Edit") / Password ("Change…"); Sync card: 28 pt
  purple circle, "Sync — updated just now" + green dot, description, NSSwitch, divider,
  "Advanced…" / "Connect Another Device…"; a "More" (…) button below. Profiles: description,
  "New windows open with" popup card, "Profiles" list (colour dot, name, chevron, drag handle),
  "Create Profile…".
- [O] Form panes (Tabs, Advanced): a two-column NSTableView over the whole window width
  (label column 387 ending 8.5 before x 382.5 window-relative, controls at x 406), first row
  32 below the toolbar, checkboxes 18 tall on a 24 pt pitch, groups ≈14 apart (single-row
  groups 44 tall). Tabs: "Tab Layout:" two 142×135 image radios (Top of Window / Sidebar);
  "General:" Extend website color into tab bar, Haptic feedback when reordering tabs, Add new
  tabs to the top, Warn before closing last tab in a Profile (all on); "Tab Groups:" ⌘-clicking
  links creates tab groups, ⌥-⇧-click opens tab in group, Automatically group tabs for
  meetings, Add emoji to new tab groups (all on); "Tab Cleanup:" "Clean up tabs I haven't used
  in:" (off) + popup "12 hours" (disabled while off). Advanced: "General:" Automatically update
  Dia; "Sounds:" Chat events, Daily report; "Address Bar:" popup "Prefer Search Engine"
  (strings: automatic / prefer chat / prefer default search engine); "When quitting Dia:" Warn
  before quitting (off) + popup "Preserve Tabs and Windows" (strings: Close Tabs and Windows /
  system setting).
- [O] Shortcuts: NSSearchField 472×26 at (19,19) with a filter (line.3.horizontal.decrease;
  menu: Customized Shortcuts, Conflicting Shortcuts) and a more button (…; Reset All
  Shortcuts); a 272 pt list card (window colour, 1 pt white ≈6% outline, radius 12) 14 below:
  11 pt semibold grey menu-title rows (Dia, File, Edit, View, Tabs…) and 36 pt action rows
  (13 pt name, shortcut 13 pt secondary right-aligned, hairline dividers); selected row filled
  95/144/229 with white text. Detail column 15 to the right: 22 pt bold title, gearshape.fill
  button at the right, 15 pt secondary description ("Create a new tab."), then a black 29 pt
  field (radius ≈8) showing the keys in 15 pt white. Unselected: "Perform common actions in Dia
  faster and from anywhere." / "Select an action to customize its keyboard shortcut."
  Strings also name a details pane: "When shortcut conflicts", "Use Website First", "Prompt
  after using on Website", "(not remappable)".
- [O] Skills: master list (/Reply, /Summarize) with +/− and an "Edit Skill" button; Apps:
  Morning Brief row, Recommended/Connected/Available app rows with Connect / Auto-connected /
  Reconnect, "Request an App". Defaults seen in ~/Library/Preferences/company.thebrowser.dia:
  nativeAdBlockEnabled, tabReorderingHapticsDisabled, shouldWarnBeforeQuitting,
  autoCleanInactiveTabsEnabled, windowRestorationSetting, shouldShareUsageData.
- Cra: `Sources/Cra/UI/Settings/` reproduces the window (NSSplitViewController + unified toolbar
  with `.sidebarTrackingSeparator`, SwiftUI panes) with panes General, Tabs, Privacy,
  Extensions, Shortcuts, Advanced; Account, Profiles, Skills and Apps have no Cra counterpart.
  New settings: `hapticFeedbackOnReorder`, `warnBeforeQuitting` (NSAlert in
  `applicationShouldTerminate`, skipped on engine relaunch), `autoArchiveEnabled`.
- [U] Light-mode colours, the popup option lists, the Shortcuts details pane, hover states
  (the source list has none), and the "Advanced Settings" ad-block dialog were not opened.
- [O] Dia 1.55.1 (9 Nov 2026, AX + 2x window capture, PR #269): the sidebar is now an inset rounded panel
  (x 8…204, 8 from the top) in a 778×600 window. AX rows are still 196×28 (the panel's width); the selected
  fill is 10 pt inside the panel on both sides (x 18…194), 28 tall, corner ≈7, (0,141,255) sRGB; glyph 20×20
  at +20 from the row, label at +49 (cap height 10 ≈ 14 pt). Cra keeps the full-height sidebar and maps
  the same relationship onto it: the fill 10 pt inside the sidebar, the glyph 10 pt into the fill.

## Sidebar header with the toolbar hidden (Arc 1.170, 26 Oct 2026)

Sources: a 1x window capture of the running Arc (light "Victor" space, sidebarWidth 347, app in the
background, pointer elsewhere), its AX tree, Victor's screenshot of the active window, and strings in
the arm64 slice. [O] = observed, [I] = inferred.

- [O] Arc's preference is `topBarURLEnabled` in company.thebrowser.Browser (View ▸ Show Toolbar).
- [O] Row 1 (AX): traffic lights 16×16 at x 12/35/58, y 16. Sidebar toggle 32×32 at x 77, y 7. Go back, Go forward
  and Reload are 32×32 at x 241/275/309 (2 pt apart, ending 6 pt from the sidebar edge), y 7. No ⌄ menu.
- [O] Refresh ⇄ stop (120 fps capture of the toolbar button without the pointer, 30 Oct 2026; click and ⌘R alike):
  when loading starts the ↻ cross-fades into the ✕ over ~10 frames (~85 ms), and back the same way when it ends.
  Fitted per frame: the old glyph shrinks 1 → ~0.7 as it fades, the new one grows ~0.7 → 1 as it appears, both on
  an ease-in-out curve (new opacity 0.02, 0.11, 0.37, 0.48 … 0.96). No rotation. Driven by the load state (Arc's
  ReloadIcon isReloading), not the press. An AXPress on "Reload this page" showed no swap at all. The system
  Replace symbol transition is NOT it: for arrow.clockwise it un-draws the arrow over ~0.8 s.
- [O] Row 2: the URL pill spans x 8…338 (8 pt in from both sides of a 347 pt sidebar), y 46…81 (36 pt), corner
  radius ≈10, fill ≈5% black over the light theme. It shows only the host ("youtube.com", no lock or globe):
  AX static text at x 20, 13 pt regular (ink 77 pt wide, the width of SF 13 regular). Favorites start at y 90.
- [O] Glyph tones, light theme: app in the background, every header glyph ≈22% black. App active (Victor's
  screenshot), enabled glyphs ≈59% black, disabled ← → ≈24%, host text ≈87%.
- [O] Victor's screenshot of the active window shows accessories at the pill's right end: pinned extensions
  (1Password, a purple "D"), a link glyph and a slider-square glyph, about 29 pt apart, the last ~19 pt from the
  pill's edge. In the background capture none of them exist in the AX tree.
- [I] They appear while the header is hovered: the binary has `isHeaderViewHovered`, `isSidebarHovered`,
  `CopyLinkContentView` and `SiteControlCenter*` types (`Arc.SidebarHeaderView`, `URLField`,
  `shouldDisplayURLField`). Their show/hide timing was not recorded, and the dark theme was not measured.

## Dia personalization tab-layout picker (Dia 1.54.2, 26 Oct 2026, static)

- [O] Strings: title "Make it yours" (Cra's), subtitle "Pick the theme color and layout that feel right for you.",
  section "Choose how you would like to view your tabs:", plus a classic-layout title and qualifier (short
  literals inlined in code, not recovered). Views: `Onboarding.PersonalizationView`, `PersonalizationContentView`,
  `PersonalizationColorButton`, `PersonalizationTabLayoutButton`.
- [O] Assets (BoostBrowser_Onboarding.bundle): `TabLayout/SidebarSelected|Unselected`,
  `TabLayout/TopOfWindowSelected|Unselected`, 230×180 pt PDFs with light and dark variants; `TabLayoutLabelText`
  black 53% / white 60%. Settings ▸ Tabs reuses the same art at 142×135 ("Top of Window" / "Sidebar").
- [O] Art geometry (pt): selected ring 3 pt (black 80% / #CCCCCC), 2 pt gap, window inset 5 pt with radius 10
  (black 5% / #333333), traffic lights 5 pt, sidebar rows 54×14 at x 10, y 27 + 19n (black 19% / #5C5C5C), page
  pane x 70…220, y 10…170 (white / #1F1F1F). The top-of-window variant has a 19 pt tab strip at black 10%.
- [O] The art panel swaps whole screenshots per colour and layout: `RebrandPersonalization<Colour>Sidebar|TopBar`
  (448×544) in BoostBrowser_Unboxing.bundle.
- Cra draws its own tiles to these measurements (no Dia artwork): the first sidebar row or a strip across the
  page marks where the address bar sits.

## Software updates (Arc 1.170, 26 Oct 2026, static + one live check)
- [O] Arc bundles Sparkle 2.9.4 (Frameworks/Sparkle.framework, CFBundleShortVersionString 2.9.4). Info.plist:
  `SUFeedURL` https://releases.arc.net/updates.xml, `SUPublicEDKey` (EdDSA-signed archives), `SUEnableAutomaticChecks`,
  `SUAutomaticallyUpdate` (download in the background), `SUScheduledCheckInterval` 28800 (8 h). No `SURequireSignedFeed`.
- [O] Module `SoftwareUpdaterClient`: SoftwareUpdateManager (SPUUpdater + SPUUpdaterDelegate), `CustomUserDriver`
  (an SPUUserDriver in place of Sparkle's windows), UpdaterWindowController/UpdaterWindowView, UpdaterStatusView,
  ReleaseNotesView, SparkleVersionComparison, `--disable-software-updater`, `--fake-updater`, feed channels
  (release, release-candidate, canary, prototype, PR, a test feed at http://localhost:8889) via setUpdaterFeedOverride.
  Driver log lines name every SPUUserDriver callback; the permission request "should never be called, because we
  set SUEnableAutomaticChecks in Info.plist".
- [O] Window copy: "Checking for updates..." (Cancel), "Your browser is up to date" (Close), "A new version is
  available" (fallback title) with release notes and "Would you like to download …", a later button, Download /
  Install, "1kB of 100MB" progress, extracting label, "Ready to Install" + "Install and Relaunch", "Installing
  update...", errors with "Download manually". ReleaseNotesView CSS: -apple-system 12px, rgb(20,20,20) / white in
  dark, li line-height 20px, links #458AFF, margin 12px 8px 16px 0.
- [O] Check for Updates…, observed live (AX menu press, window-id capture): the Arc menu reads About Arc / Settings… /
  Share Arc / Set as Default Browser / Import from Another Browser… / Check for Updates… The up-to-date window is
  270 × 342 with no title (traffic lights only), window background, the app icon 64 pt (84 pt AX frame at y 53, art
  x 109–160 y 69–120), "Arc" 24 pt bold label colour (frame y 147, 30 tall), "1.170.0 (89123)" 11 pt (y 175, 16
  tall), "Your browser is up to date" 13 pt (y 209, 208 wide), both white 50% in dark mode; "Close" button fill
  170 × 48 at (50, 256), continuous radius ≈6 (fitted to the corner's anti-aliasing), a faint shadow, label 13 pt bold
  at white ≈80%. `UpdaterButtonBackgroundColor` asset: white, black in dark appearance. The other states were not
  reachable (Arc was current).
- [O] Sidebar banners (SidebarBanner module, AppData+SidebarBanner): `updateAvailable` "An update is ready!" / "Click
  to restart" (action "Restart and Update"), "New Arc Version Available", and after the restart `updateSummary`
  ("Updated!", "Update Complete!", "See What's New" opening the release notes; V2 with heart.circle.fill and the
  update-heart-animation Lottie). Defaults: `autoUpdateBannerDismissalCount` (41 on this Mac),
  `currentUpdateAvailableSince`, `currentUpdateDownloadedSince`, `lastInstalledAppVersion`,
  `firstLaunchAfterUpdatedFromVersion`, `lastUpdateWasAutoUpdate`, `automaticUpdateWillRelaunchApp`.
  `forceShowUpdateBanner` is read at launch only (a new window did not show it); the banner was not captured.
- [O] Automatic restart: analytics keys auto_update_queued, ignore_user_idle, is_auto_update_enabled,
  is_ready_to_install_update, time_since_last_active, active_tabs_blocked_update, window_dialog_sheet_visible,
  incognito_windows_with_web_contents_exist, sleep_satisfied_for_auto_update, forced_auto_update_occurred; remote
  flags auto-updates-enabled, new-auto-update-heuristic-enabled, auto-update-inactivity-delay-in-seconds,
  auto-update-required-idle-duration-in-seconds; logs "Auto update was cancelled because in progress download was
  detected" and "… one of the web contents reported unsaved work". Little Arc windows are restored only after an
  auto-update restart. Settings: "Automatically update my Arc" (`automaticallyUpdateArc`) with "Learn more about
  auto-updating". [U] the flag values (remote).
- Cra: `Services/SoftwareUpdater.swift` (Sparkle 2.10 from vendor/sparkle, same Info.plist keys, feed
  github.com/VictorKildahl/cra/releases/latest/download/appcast.xml written by scripts/appcast.sh), the updater window
  (`UI/Updates/UpdaterWindow.swift`, pixel-matched to the capture above), sidebar banners (`UI/Updates/UpdateBanner.swift`,
  Arc's copy, Cra's card style since Arc's was not captured), Cra menu ▸ Check for Updates… after the import item,
  Settings ▸ Advanced ▸ "Automatically update Cra". The automatic restart waits for 10 min in the background with
  2 min without input, or 30 min without input, and holds off for downloads, sheets, Little Windows, Picture in
  Picture, the import and any power assertion Cra holds (Chromium's media wake locks); the relaunch doesn't take focus.
  Verified with local appcasts (renamed CraUpd test bundle, LSEnvironment for the relaunch): background download →
  banner → idle restart, auto-download off → "New Cra Version Available" → Download → Install and Relaunch, and the
  "Cra Updated!" banner after each, all ad-hoc signed.

## Air Traffic Control (Arc 1.170, 26 Oct 2026, live via AX + window captures)

- [O] Settings ▸ Links ends with a card "Choose where links open inside Arc. ⓘ" and an "Air Traffic Control…" button,
  which opens a 508 × 500 sheet: "Air Traffic Control" 13 pt bold at (24, 37), "New Route" 122 × 28 at (306, 32), a
  32 × 32 close ✕ at (452, 30), a hairline, the route list (scroll area at (24, 92), 460 wide), a hairline at y 410,
  "Default" at (60, 438) with a 165 × 24 popup at (164, 434). Each route is two lines on a 76 pt pitch, 52 pt tall:
  "🔗 URL" (secondary, x 55) · match popup 110 × 24 at x 112 ("Is equal to" / "Contains") · text field 210 × 24 at
  x 230 (placeholder "arc.net") · 13 pt ⊖ remove at x 449; then "↳ Open in" at x 129 with a 165 × 24 popup at x 207,
  28 pt below. Destination menu: disabled header "Open in Space", "Most Recent Space", every space (emoji + title),
  separator, "Little Arc". New Route appends `Contains`, empty, Most Recent Space at the bottom.
- [O] Storage `StorableLinkRouting.json`: `{rules: [{id, sourceComponents: [{id, componentType: {urlMatch: {_0:
  {contains: {}} | {matches: {}}, _1: "meet.google.com"}}}], destination}], defaultDestination, version: 1}` with
  destinations `{space: {_0: {mostRecent: {}}}}` and `{littleArc: {_0: {mostRecent: {}}}}` (the inner value is the
  profile). Swift types: LinkMatchingRule, LinkSourceComponent.ComponentType (only `urlMatch`),
  LinkSourceTextMatchingStyle, LinkDestination, ProfileDestination. Arc seeds a meet.google.com route
  (`didSetDefaultGoogleMeetRoute`).
- [O] "Links from other apps open in Little Arc" *is* the default destination: switching it off rewrote
  defaultDestination to `space(mostRecent)`, on to `littleArc`.
- [O] Swift metadata (`__swift5_fieldmd`, arm64 slice): `LinkDestination = space(ProfileDestination) |
  littleArc(ProfileDestination)`, `ProfileDestination = mostRecent | space(UUID) | profile(…)`, so a specific space is
  stored as `{space: {_0: {space: {_0: "<space id>"}}}}`. `LinkMatchingRule {id, sourceComponents, destination}`,
  `LinkSourceComponent.ComponentType = urlMatch(LinkSourceTextMatchingStyle, String)`, style `matches | contains`.
  Only `Arc.AppReducer` and `Arc.WindowsReducer` hold the LinkRoutingClient (routing happens where URLs are opened).
  The editor (`LinkRoutingEditor`) has a `focusedRuleID` and ComponentAction `add/delete/submit`; Return in a route
  field did not add a second condition. Analytics: LinkRoutingWindowType `littleArc | mainWindow | customSpace`,
  LinkRoutingURLMatchType `equals | contains`, property `autoRouted`. `AppState+DefaultLinkRoutes.swift` seeds the
  meet.google.com → Most Recent Space route once.
- [O] Runtime (26 Oct 2026, temporary routes written to StorableLinkRouting.json while Arc was quit, links handed over
  with `open -g -a Arc <url>`, landing read from the AX tree and StorableSidebar.json, file restored afterwards):
  - Both the URL and the route text lose case, the scheme and a leading `www.` before comparing: "Contains
    https://example.com/atc-scheme" matched `http://example.com/…` and `https://www.example.com/…`; "Contains
    ATC-CASE" matched `/atc-case`.
  - "Contains" also sees the query and fragment (`?x=atc-order`, `#atc-recent` matched).
  - "Is equal to" compares host and path only: `example.com/atc-eq` matched `…/atc-eq?x=1`, `…/atc-eq#frag`,
    `http://`, `www.`, upper case and a trailing slash, but not `…/atc-eq/more`.
  - Routes are checked in order; the first match wins. No match → the default (Little Arc).
  - A space destination opens a new foreground tab at the top of that space's Today list (a second copy when the URL
    is already open) and switches the main window to the space. Most Recent Space = the space the main window last
    showed.
  - `littleArc(space(JYSK))` opened a Little Arc whose button read "Open in Victor" (the most recent space); the
    editor shows that destination blank. The payload only picks a profile.
- [U] what several conditions in one rule mean (any vs all; the UI never creates them), the ⓘ help article URL
  (built at run time, `featuresForLinkRouting`), the empty-list state.
- Cra: `Packages/CraCore/Sources/CraCore/LinkRouting.swift` (Arc's matching above, checked against every observed case; first match wins; the
  Google Meet route is seeded once), `AppSettings.linkRoutes` / `defaultLinkDestination` (the Little Window checkbox is a view of the
  default; old `openExternalLinksInLittleWindow` values migrate), `AppDelegate.openExternalURL`, Settings ▸ Tabs ▸
  Links ▸ "Air Traffic Control…" (`UI/Settings/AirTrafficControlView.swift`, Arc's geometry within 1 pt, 440 tall to
  fit Cra's Settings window, the window's own background instead of Arc's navy). The Arc import brings the routes
  and default along, matching spaces by title. Compare: docs/screenshots/compare-air-traffic-control.png.
  Past Arc (#258): a Little Window destination can name a space, `littleWindow(space:)`, picked in a second popup
  under "Little Window"; the page loads in that space's profile and "Open in" / ⌘O names it. Saved as
  `{"littleWindow": {"space": "<id>"}}` (`{}` without one, as before), which older Cra reads as a plain Little
  Window. An imported `littleArc(space(id))` keeps its space.

## Extension popups and extension windows (Arc 1.170, 26 Oct 2026, static)

Method: `strings`, `otool -oV` with relative-method-list selectors resolved by hand, and Swift field metadata
(`__swift5_types` → field descriptors) of the arm64 slices of `Arc` and `ArcCore.framework`. No runtime capture of
Arc's popup this time, so geometry is not measured.

- [O, Arc 1.172.2, 11 Nov 2026, arm64 disassembly + Objective-C metadata] `BrowserExtensionWindow`'s Swift
  initializer at `0x100108374` calls `setCollectionBehavior:` with `0x100` at `0x100108534`:
  `.fullScreenAuxiliary`. The selector stub at `0x103664220` reads the selector reference at `0x1045483c8`.
  The window is an ordinary `NSWindow`, not a nonactivating panel. Shared window configuration at
  `0x1002c71f0` also has paths that set `.fullScreenAuxiliary`, clear `.fullScreenPrimary` and add
  `.moveToActiveSpace` (`0x2`). [U] The particular shared-configuration path used by Bitwarden's separate
  unlock window, and its live Space membership, were not measured. `ADKApplication.didCreateNewBrowser:`
  (`0x1004bc9b4`) wraps the browser and passes it to a Swift delegate through an indirect call.
  Read again in the review of #351: the stub's selector reference resolves to `setCollectionBehavior:`, and the
  shared path at `0x1002c7290`–`0x1002c72c8` ORs `0x100`, ANDs out `0x80` and ORs `0x2`, in that order. Cra does
  the three only for a window that opens over a full-screen Cra: Chromium never takes a `.fullScreenAuxiliary`
  window full screen (`gfx::SetNSWindowCanFullscreen` returns early), so over a windowed Cra the window stays
  as Chrome made it (scenario `extension-popup-own-fullscreen`).
- [O] ArcCore's browser delegate hands the toolbar popup to the Swift shell as web contents:
  `browser:didOpenExtensionPopup:webContents:`, `browser:didResizeExtensionPopup:size:`,
  `browser:didCloseExtensionPopup:` (`ADKClientLive.BrowserExtensionsPopUpManager`). The window state keeps
  `WindowState.browserExtensionPopup: BrowserExtensionPopup? {extensionID, size, browserID}` and
  `WindowViewController` / `LittleWindowViewController` own a `browserExtensionWindowController`.
- [O] `Arc.BrowserExtensionWindow: NSWindow` (fields store, viewStore, defaultSize; "Expected an extension
  popupView, but there wasn't one.") and `BrowserExtensionWindowController: NSWindowController` (delegate,
  `savedDefaultWindowFrameKey`, `userHasMovedWindow`, `closeCurrentItem:`, `windowDidBecomeKey:`,
  `onWindowWillMove:`; autosave name `.browserExtensionWindowAutosaveFrame`).
  [I] The popup is a separate window under the toolbar that the user can drag; once moved, its frame is remembered.
  Every popup takes this path, whatever opened it (toolbar click, keyboard command, `chrome.action.openPopup()`).
- [O] Windows an extension creates: ArcCore `createPopupBrowser:withDelegate:` / `didCreateNewBrowser:`,
  `ChromiumBrowser.browserType: BrowserType {normal, popup, pictureInPicture}` and `OpenDisposition.popup`. Popup-type
  browsers stay popups; Arc's tabs live in normal Chrome windows.
- [O] Arc ships a list of password-manager extension IDs (`PasswordManagerExtensionID`: 1Password, its beta and
  nightly builds, Bitwarden, Dashlane, LastPass, iCloud Passwords, Keeper, RoboForm, NordPass), plus a hard-coded
  `chrome-extension://pejdijmoenmkgeppbflobdenhhabjlaj/page_popup.html?popupWindow=1` ([I] iCloud Passwords).
- Cra (Chromium side, observed with a probe extension and the DevTools port):
  - CEF creates every `CefBrowserView` browser as `TYPE_POPUP` (trusted). To extensions every Cra tab therefore
    sits in a `"popup"` window (`windows.getAll()` returns only popups), and `chrome.action.openPopup()` fails with
    "Browser window has no toolbar." (`PopupBrowserSupportsWindowFeature(kFeatureToolbar)` is false). 1Password
    calls `openPopup()` from its inline menu and checks `windows.getCurrent().type === "popup"`; its
    `windows.onCreated` handler treats every new Cra tab as a sign-in popup from the previous tab.
    `scripts/cef-patches/extensions-normal-windows.patch` reports `IsViewsHosted()` browsers as `"normal"` and lets
    them open popups (needs a CEF build; not in the CEF 154 codecs1 build).
  - `windows.create({type: "popup"})` used to become a Cra tab (StrayBrowserClient). Chrome gives tabbed windows
    `NSWindowStyleMaskFullSizeContentView` (BrowserNativeWidgetMac::PopulateCreateWindowParams) and popups a plain
    titled window, so Cra now keeps the latter as Chrome's own window (`+[CraCEFRuntime isExtensionWindow:]`, ⌘W
    closes it). The window does not exist yet in OnAfterCreated (GetWindowHandle is nil); it does by OnBeforeBrowse.
  - Popups Cra did not open itself (shortcut, `openPopup()`) are found through `Target.setDiscoverTargets`: the
    target is created as `"other"` with no URL and gets the popup URL in `targetInfoChanged`; Chrome creates the
    bubble window hidden before that, so placement looks for a newly *visible* borderless window. Without this the
    popup hangs off Chrome's hidden toolbar (x ≈ 174 pt from the left).
  - [U] Not reproduced from Arc: the popup window's chrome (shadow, corner radius, drag handle) and where it reopens
    after being dragged; Cra still uses Chrome's bubble.

## Site Control Center and pinned extensions (Arc 1.170, 26 Oct 2026, live via AX + captures)

- [O] The right group's spacing (Arc 1.171, window captures and AX frames, 8 Nov 2026), all 5 pt in from the card
  edge: normal bar, pinned extensions, sliders, Split View as 32 pt boxes 4 pt apart, icons centred 21, 57, 93,
  129 pt from the edge; a focused split pane ends in Split View Options and Close Split View Pane (32 pt, edge to
  edge, centred 53 and 21), the sliders 4 pt before them (89) and the pins on from there (125, 161); an unfocused
  or empty pane keeps only the close, centred 21; the developer bar has Extensions Menu, pinned extensions, Split
  View Menu as 28 pt boxes edge to edge (centred 103, 75, 47, 19 with two pins), 16.5 pt after Inspect Element.
  Cra matches all three (toolbar-pinned-extensions scenario).
- [O] The toolbar's sliders button is "Site Control Center" (32×28 at the bar's right end, after the pinned extension
  icons at a 36 pt pitch; `SiteControlCenterView` in ARC_SiteControlCenter). It opens an `AXPopover` 262 wide whose
  content column is 236 wide, inset 13; the popover's top sits 4 pt above the bar's bottom edge.
- [O] Column, top to bottom: four 48×32 action buttons on a 56 pt pitch (Share, New Boost, "Capture a portion of this
  page", "Capture the full page"; raised: gradient #363636→#212121, top edge #69696A, outline #141115), 11 pt;
  "Extensions" 14 pt bold #D4D4D5 (hovering the section shows "Manage" 12 pt #959496 at the right; it opens
  extension management), 10 pt; a 4-column grid of 48×32 tiles (#353436, hover #39383B) on 56/40 pt pitches:
  pinned extensions in pin order, then the rest by name, then a "+" tile (Add Extension); 15 pt; "Settings", 10 pt;
  208×33 rows on a 43 pt pitch (32 pt circle #F0F1FE when on, #6A6A6F when off; title 14 pt semibold #DBDBDB,
  subtitle 13 pt #979798): Developer Mode On/Off, Block Ads & Trackers On/Off, Automatic Picture-In-Picture Allowed;
  a divider; footer: "Secure" pill 82×32 (#363536) and a 32 pt "More" circle (#403F40). Background #272728 (dark theme).
- [O] Pinning: each tile carries a 14 pt `pin.fill` badge at (+37, +21) from its top-left. Pinned tiles always show
  it (#F0F1FE, AX "Unpin"); an unpinned tile shows it on hover only (#7F7E85, AX "Pin"). The badge glyph is the
  popover's background colour.
- [O] More menu items (strings): Clear Cache, Clear Cookies, Manage Extensions, Add Extension, All Site Settings
  (plus Boost items).
- [O] Extension popup window (user screenshot): ≈472×380 pt titled window, ≈25 pt title bar with a red close button and
  disabled minimize/zoom, the popup page filling the rest.
- [O] Clicks while a popup is up (2 Nov 2026, live: HID clicks, CGWindowList sampled every 15 ms, AX focused window;
  Detailed SEO and 1Password pinned): the popup window is key, so the browser window is inactive. A click in the
  normal toolbar only takes focus back, which closes the popup: its own button leaves it closed (nothing reopens
  within 3.5 s), 1Password's button closes Detailed SEO's popup and opens nothing (one plain click opens it), and
  Split View Menu opens no menu (it does on a plain click). The developer bar's Extensions Menu did act on that
  click (popup closed and the Site Control Center opened); its Detailed SEO tile then did nothing on the first
  click. Cra: `FirstClick` (CraCore), GitHub #87. [U] Back/reload/URL: Arc's popup covered them.
- Cra: `UI/SiteControlCenter.swift` (same geometry; Cra's popover lands at Arc's exact screen coordinates), the
  second action is Copy URL (no Boosts), Capture = visible page, Capture full page = DevTools
  `Page.captureScreenshot` with `captureBeyondViewport`; Clear Cookies = `Storage.clearDataForOrigin`, Clear Cache =
  `Network.clearBrowserCache`, both reload. Pins live in `pinned-extensions.json`; when that file does not exist yet
  Cra takes Arc's (then Dia's, then Chrome's) `extensions.pinned_extensions`. The popup frame is
  `UI/Windows/ExtensionPopupWindow.swift` (Chrome's bubble as a child; the frame never becomes key, since Chrome
  closes popups that lose focus, so its traffic lights are drawn by Cra).
- [U] Arc's "disabled" subtitle wording for Picture-in-Picture (Cra says "Disabled"); the Secure pill's click action.
- Popup size (Arc inherits Chrome's rule): the popup page's own size, at least 25×25 and at most 800×600, following
  the page as it changes. When Cra has no page to hang Chrome's real popup on (no tab open, no DevTools pipe) it used
  to load the popup page into a 1000×700 Little Window; it now uses `ExtensionPageWindow` (same frame, the page's
  max-content width and its height at that width, re-measured every 250 ms, closes when it loses focus).
- Chrome-style page windows that Cra re-parents keep Chrome's `BridgedContentView` at y −22 (where the title bar ended):
  the page is drawn 22 pt low and its bottom cut off unless the content view is reset to the full window frame
  (MainWindowController.fillContentView did this for tabs; Little Windows and the popup window now do too).

## Downloads and Chrome's download bubble (Arc 1.170, 27 Oct 2026, static strings + Cra test)

- Arc never shows Chromium's download UI. Downloads go through ADK (`ADK.ContextDownloadDelegate`,
  `ArcBrowserContextDownloadsDelegate`, `ADKClient/DownloadManager.swift`) into Arc's own views:
  `DownloadsUI.DownloadToLibraryWindowController`, the Library's downloads page (`HomeButton/DownloadsPageReducer`,
  `DownloadsContentView`, filter by profile), Little Arc's `LittleBrowserDownloadsTrayViewController`, plus Tidy
  Downloads renaming (`DownloadRenamedToastContentView`). Arc's Chromium profile sets no `download_bubble.*` pref:
  Chrome's toolbar UI simply isn't there.
- Cra (CEF Chrome style) handles every download itself (OnBeforeDownload returns true), but Chrome's bubble still
  popped up when a download finished: a window titled "Recent Download History" (320×120 for one item), invisible
  with no toolbar to anchor to, which swallowed the next click on the page. Cra turns it off the way Chrome's
  "Show downloads when they're done" setting does: `download_bubble.partial_view_enabled` = false on the global and
  incognito request contexts (CraCEF.mm HideDownloadBubble). Verified in a test instance: no bubble window, the first
  click after a download reaches the page.
- Arc has no download toast. A running download, a failed one ("Failed to Download") and paused or cancelled ones are
  rows in its downloads list, with a speed ("e.g. 3 MB/s"); finished ones read "54 seconds ago". Cra's bottom-right
  download cards (its only other toast design) are gone (2 Nov 2026, #85 follow-up): the hover list shows running,
  failed and cancelled downloads too (DownloadHistory.live, DownloadRow). [U] Arc's exact wording and icon for a
  running or failed row (Cra: "81.3 MB of 104.9 MB — 30.1 MB/s", the file type's icon) — to capture live.
- Acting on a download (Arc 1.172.1, 9 Nov 2026, #272; strings of 15 bytes or fewer decoded from the mov/movk
  immediates of `otool -tV`):
  - "Download Context Menu" (ContextMenus): `Open %@`, `Copy %@`, Show in Finder, separator, Cancel Download,
    separator, Hide from Arc, Move to Trash. %@ is the file's kind from ARCFoundationBase's URL+DownloadDestination,
    tested in order with UTType.conforms: Image, Disk Image, PDF, Movie, Audio, Zip Archive, Archive; with no match
    it is the file's extension as it is (`URL.pathExtension`, "Open txt"). Cra: CraCore `DownloadMenu`, the tray and
    Library ▸ Downloads share it (DownloadRowMenu); "Hide from Cra". Which items each state gets was not read; Cra
    gives finished files the first and third groups, running ones Show in Finder and Cancel Download.
  - Paused rows read "Paused" ("Subtitle copy for a paused download"); no item pauses one. Cra adds Pause Download /
    Resume Download beside Cancel Download (CEF's CefDownloadItemCallback, kept per id in CraCEF.mm).
  - Quitting while downloads run (`applicationShouldTerminate`): "Downloads in progress", "There are downloads in
    progress. Closing the application will cancel them.", buttons "Close " + the app's name and "Keep browsing".
    Cra: `QuitPrompt` asks it instead of "Quit Cra?", and before Install and Relaunch.
  - The automatic update restart waits for downloads ("Auto update was cancelled because in progress download was
    detected."); Cra has done so since 0.1.x (`autoUpdateBlocker`).
  - `DownloadProgressBadge` (BaseHomeComponents): fields progress, colorPalette, reduceMotion, progressRingOpacity,
    overallOpacity, overallScale, completionScale, completionOpacity, iconName, iconSize; the track colour asset is
    DownloadProgressBarBackground. A ring with an icon, a completion mark that scales in, the whole badge scaling and
    fading. [U] Where Arc draws it and its sizes: Cra puts a 16 pt one on the download bin's corner
    (DownloadProgressBadgeView) and keeps the bin up while downloads run — to compare live.
- Chrome's download-started animation (DownloadBubbleStartedAnimationViews, Chromium 156.0.8078.48): a views popup
  parented to the page, `accept_events = false`, 2 × kIconBackgroundRadius 32 = 64×64 pt, 500 ms, flying to the hidden
  toolbar's download button. Only reduced motion turns it off (CEF_CTBT_DOWNLOAD is deprecated: downloads became a
  pinned toolbar action). Cra orders that window out as it appears (ChromeDownloadAnimation, a 2 s watch after each
  new download); verified: every sighting of the 64×64 window was off screen.

### Arc's download animation (DownloadsUI.DownloadToLibrary, live, 60 fps app-only ScreenCaptureKit captures)

ObjC metadata: `DownloadToLibrary.ViewModel` (_downloads, _binPositionX, windowSize, binPositionXAnimator, showsBin,
animationGroup), `DownloadViewModel` (source, destination, _projectileIconKeyframeAnimation, _iconOffsetX,
iconOffsetXAnimator, iconBounceAnimator, lazy g / vx0 / vy0 / projectileMotionDuration / apex / apexTime),
`WindowController` (parentWindow, dismiss, isAnimating): a window over the browser window. Measured (window 1728×1084):
- Source is the pointer (logged with `cliclick p` every 30 ms): the glyph launched at the pointer; with the pointer off
  to the right of the window it entered from the window's edge. Destination is the bin.
- Projectile: constant horizontal speed (−1232 pt/s on a 1361 pt run, every frame within ~10 pt), apex 90 pt above
  the launch point, g ≈ 2630 pt/s²; 1.10 s from the top of the page to the bin.
- Glyph: navy disc #04072A, ring #EFEFFF, white down arrow, faint blue glow. Ring diameter 32 pt at launch, 48 pt at the
  apex, then linear down to ~10 pt at the bin; opacity rises linearly to 1 by the apex; the arrow reads ↘ early and
  ↓ by mid-flight.
- Bin: the file's Quick Look thumbnail (a .txt showed its text on a white page), 32 pt, ~8 pt corners, resting 9 pt
  right of and 12 pt above the Library glyph's centre (the glyph's box peeks out under it). It appears with the launch
  6 pt high, drops to 12 pt low at ~0.15 s, back to −2 pt, settled by ~0.4 s. Faint grey while Arc's window is in
  the background, white when it is key. It leaves 30 s after the glyph lands (appeared 8.47 s, faded 39.37-39.53 s
  in a 60 fps capture), fading over 0.15 s, the same with Arc in front or behind.
- With Tidy Downloads on, Arc also shows a "Download renamed to:" card above the bin (see "Tidy Downloads").
- Cra: DownloadFlight (overlay panel, Core Animation keyframes sampled from the same projectile) and DownloadBin in
  SpaceDock. Verified side by side with fixed-source test builds.
- Tidy Downloads card (only with Arc Max's renaming): see "Tidy Downloads" below (built 4 Nov 2026).

### Arc's downloads list on hovering the Library button (live, 60 fps, 1728×1084 window)

- Rows for the recent downloads still on disk, oldest at the top, the newest ending 2 pt below the list viewport
  (just above the dock). Rows 56 pt apart: 40 pt thumbnail (Quick Look, 6 pt corners) at x 8, the file name at
  x 61 in 14 pt white 82 %, "54 seconds ago" (RelativeDateTimeFormatter, full) in 12 pt white 50 %. Four rows were
  observed with four downloads available; the maximum is unknown (Cra shows five).
- The tab list behind is hidden from 3 pt above the first row and fades back in linearly over the 170 pt above it.
- Opens 0.2 s into the hover: rows fade in and rise 5 pt in ~0.12 s, bottom row first, ~25 ms apart; the fade comes
  in over ~0.18 s. Closes ~0.07 s after the pointer leaves: rows gone within ~0.05 s (bottom first), the fade
  out over ~0.13 s. Arc's own "View Library ⇧⌘L" tooltip shows meanwhile (beside the button, see "Space dock
  tooltip").
- Cra: DownloadsTray / DownloadsTrayMask (sidebar), DownloadHistory (downloads.json). The mask must be a single
  GeometryReader gradient: fixed-height layers in it raised the sidebar's minimum height and the window grew.

## Tab switcher (Arc 1.170, 27 Oct 2026, live: 100 fps region recordings + 1× stills)

Arc's `ModalItemSwitcher` (`ModalItemSwitcherWindowController`, `ModalItemSwitcherSnapshotUpdateCancellableID`;
strings "Opens the tab switcher, where you can cycle through recent tabs like Command+Tab on your computer!" and
"Cycles backwards through your most recent tabs…"). Arc's help centre: the five most recently visited tabs.

- **List:** the focused space's tabs by `timeLastActiveAt`, newest first (checked against StorableSidebar.json: the
  JYSK space's top four plus one more JYSK tab, skipping a newer one in another space). The current tab is card 0.
- **A tab opened in the background** (⌘-click) is card 1 at once: ⌃Tab goes to it and a second tap comes back
  ([O live] contributor, PR #394, 12 Nov 2026). Arc's StorableSidebar.json agrees that `timeLastActiveAt` is set when
  a tab is created: tabs there carry it equal to `createdAt` to the microsecond. Cra stamps a tab opened with
  `select: false` when it opens and keeps the window's current tab first (`SidebarStore.recentTabs`), scenario
  `tab-switcher-background-tab`.
- **Keys:** ⌃Tab opens on card 1 and moves on; ⇧Tab, ← and → move too. All of them wrap at both ends. Releasing ⌃
  switches, Esc cancels (the tab stays). A tap (⌃ up 0.13 s after Tab) switches with no panel; the panel appeared
  0.18–0.26 s after the key, so there is a short show delay.
- **Pointer:** moving over a card selects it (no separate hover style). It stays selected after the pointer leaves.
- **No animation:** the panel appears, moves its selection and closes from one frame to the next.
- **Geometry (pt):** centred on the whole window (sidebar included), integral origin. Panel 941×190 for five cards:
  16.5 left/right, 16 top/bottom, cards 180×158 on a 182 pitch. Thumbnail 158×105 at (11.5, 12), corners about 6.5
  (continuous), soft shadow below. Title row under it: favicon 16×16 at (13.5, 130.5), title 8 pt after it, SF 14
  medium (ink width of "Example Domain" 108 px, "DL nine" 48 px, cap top to baseline 148–160 from the panel top), tail
  truncation. Panel corners continuous ≈ 26, card highlight ≈ 8.
- **Colours (dark):** panel #1C1B1A, 1 px outer line #030303, 1 px inner line #504F4F (white 23%). Empty thumbnail
  #1C1C1C. Missing favicon: a rounded square, white 14%. Selected card: the space's semantic `hover` colour
  (JYSK dark: extended sRGB 0.360/0.392/1.019 at α 0.48, measured 58/61/136 over the panel). In Arc's data both
  spaces' dark `hover` sit at OKLab L ≈ 0.60 in the theme's hue near sRGB's maximum chroma; Cra derives it that way
  from the theme accent. Light appearance not observed (the Mac runs dark); Cra's light colours are a guess.
- **Cra test (CraTK, pid-targeted keys):** geometry, borders, text and favicon position match Arc's captures to the
  pixel. Thumbnails come from `Page.captureScreenshot` of the visible viewport (Chromium draws nothing for hidden
  pages), taken 1 s after a tab shows or finishes loading and again for the current tab when the switcher opens.

### Space dock tooltip and tooltip tones (Arc 1.171, 3 Nov 2026, issue #152, offline Arc + Arc's data)

- [O data] Every tip in a browser window takes the palette of the space that window is in, whichever control or
  space icon it belongs to (`ArcTooltipConfiguration.colorPalette`). Hovering the Work icon while Personal is
  focused gives "Work" in Personal's yellow-brown; the Library tip changes with the space too. The four tones
  are slots of the semantic palette, and all four are mixes of `primaryColorPalette.shadedDark` (=
  `light.maxContrastColor`), checked on Victor's yellow theme and Arc's default theme (StorableSidebar.json),
  and on the issue's CloudDev and RM: fill = `dark.background` = shadedDark × 0.30; text = `dark.title` =
  white with 15 % of shadedDark; pill and key caps = `light.hover` = white with 20 %; profile name, avatar and
  cap glyphs = shadedDark. Cap edge = halfway between the cap face and the glyph colour (160/148/97 measured,
  161/146/96 predicted). Ring: one device pixel of white at 10 % over the fill (on Arc's default theme exactly
  Little Arc's `#22255D` around `#0A0D4B`, which is that theme's fill: Little Arc uses the default palette).
  The navy measured on 27 Oct was the default theme's: the JYSK space has no windowTheme.
- [O live, 2x] Space icon tip: "<space> [☺ <profile>] ⌃N". A Default-profile space says "Default" (Arc's
  Local State calls that profile "Your Arc"); N is the space's place in the order. Capsule 28 pt, centred on the
  icon, its bottom 19.75 pt above the icon's centre. Name 12 pt medium, 10 pt in; profile pill 6 pt after it,
  22 pt tall, 3 pt from the capsule's edges: avatar 14 pt, 6 pt in and centred, then the name in 11 pt medium
  (cap height 8 pt against the title's 9) 3 pt on, 6 pt to the pill's end (pill = 29 pt + the name). Caps 6 pt
  on, 19 × 19 pt, 3 pt apart, 10 pt to the capsule's end; each a face inset 1 pt on the sides and top and 2.5 pt
  at the bottom over the darker edge. "View Library ⇧⌘L" uses the same caps; its tip hangs 19.5 pt right of the
  button's centre, centred on it. Widths: Personal 191.5, Work 160, View Library 161.5 pt.
- [O live] Avatar: `ARC_ProfilesUI.bundle` "archie", a 14 pt template image: disc at alpha 26/255, two upright
  eyes and a smile at full alpha, drawn in the ink. The same glyph on every profile.
- [O live, 120 Hz] The dock tip shows ~0.6 s after the pointer stops (0.62–0.65 s in two recordings), sooner
  than a control's 1.6 s. Moving along the icons replaces it in place in one frame. The cell's hover fill fades
  in over ~0.2 s.
- Cra: `ArcTooltipController.tones` (AppDelegate: the window's focused space → CraCore `TooltipTones`, nil and
  Little Arc's navy elsewhere); `SpaceTheme.shadedDark` rebuilds Arc's shade from the theme colour (the hue at
  10 % luminance, the rule Now Playing already used); `SpaceCellView` gives the name, the profile and
  `space<N>`'s keys; `ProfilePill` / `ProfileAvatarView` (the smiley redrawn as a path, fitted to the image's
  pixels at RMS 1.7/255). Compared side by side with Arc in both themes: widths within 1 px at 2x, tones
  within ~5/255 where Arc's shade stays in the sRGB gamut. The dock's timer is 0.55 s: with a real pointer Cra's
  tip reached the screen 0.69 s after the last move at 0.6. The dock enters the new cell before leaving the
  others, so the tip is replaced in place either way (it used to fade one out while the next popped in, moving
  right). Not done: the cell's hover-fill fade.

### Space dock: press area, fills and reordering (Arc 1.170, 27 Oct 2026, ObjC metadata + AX tree + captures)

- [O static] `SidebarDock.SidebarDockView` holds an NSCollectionView (`SidebarDockCollectionViewLayout`, with
  `draggingIndexPaths`, `proposedDropIndexPath`, `dropTargets`, `layoutAttributesForInterItemGapBeforeIndexPath:`,
  `layoutAttributesForDropTargetAtPoint:`), so spaces reorder through the collection view's own drag and drop
  with a gap opening at the proposed index. `SidebarDockItemView` overrides `mouseDown:`/`mouseUp:` and has a
  `backgroundLayer`, `_controlState`, `activeIconView`/`inactiveIconView`, a `pageIndicator` and `menuForEvent:`.
  It has no tracking-area methods of its own.
- [O static] "Drag to Reorder Space" ("Tooltip; Drag target to reorder a space.") belongs to `Arc.SpaceControlsView`
  (the space header controls), not to the dock.
- [O AX, 1728×1084 window] each space is an AXButton (role description "Space", title = space name), frame 36×34 on
  a 34 pt pitch inside a 68×32 section for two spaces, so the hit cells (34×32) touch with no gap. The strip is a
  263×50 scroll area centred between the 32×32 Library button (x 8, 9 pt above the bottom) and the 32×32 "+" button
  (8 pt from the sidebar edge).
- [O live, 9 Nov 2026, Arc 1.172.1 offline copy, 1x sRGB captures + AX, PR #271] The + (`sidebarPlusButton`, no tooltip)
  opens `ArcMenu`: a borderless 222×308 window whose fill is 210×290 (radius 12) with a 12 pt tail under it, 3.5 pt
  left of the button's centre (194 pt into the fill), the tip 10 pt above the button. Rows 194×40 at y 8, 48 | 105,
  145 | 202, 242, separators 1 pt at y 96 and 193 (x 10…200): New Space, New Folder | New Easel ⌃⇧E, New Boost |
  New Split ⌃+, New Tab ⌘T. It opens with New Tab picked. Boost is off without a web page, Split without a tab.
  Colours from the space's DARK semantic palette on light spaces too: fill backgroundExtra, hover and separators
  hover at 0.48 over it, shortcuts subtitle, disabled (121,120,129); titles 13 pt semibold white 51 pt in,
  shortcuts end 21 pt from the edge. Timings (static, disassembly): open 0.1 s scale from 0.95 + 0.05 s fade,
  close 0.07 s, curve (0.215, 0.61, 0.355, 1). The + (14×14, 2 pt arms) turns 45° into × with ≈13 % overshoot,
  settled ≈0.18 s. Glyphs for Space, Tab, Split and Boost are Arc's own PDFs; Cra uses the nearest SF Symbols.
  Cra: SidebarCreationMenu, CraCore ArcMenuTones.
- [O capture, Victor's screenshot] pressed cell: 34×32, ~6 pt circular corners, fill 39,33,51 over 21,14,34, i.e. white
  at ~7.8%.
- [U] Arc's hover fill could not be recorded (live pointer runs were cut short while Victor was at the Mac); the pressed
  value is used for hover too, and the light-theme fill (black 5%) is a guess. Arc's drag image follows the pointer
  freely (system drag session); Cra keeps the dragged icon on the dock's row.
- Cra: `SpaceDock` draws 34×32 contiguous cells in SwiftUI; an AppKit view over the strip (`SpaceDockMouse`) takes
  the mouse like Arc's item view: `mouseDownCanMoveWindow` false (a press there never moves the window), hover from
  its own tracking area, click on mouse-up inside the pressed cell, horizontal drag reorders (neighbours slide a cell
  aside, the icon settles, then `moveSpace`), right-click menu via `menu(for:)`. 0.1.13 used a SwiftUI
  `DragGesture(minimumDistance: 0)` per cell plus a `CraWindow` press guard instead; that dropped every other click
  (the window got the press, the gesture never began), so spaces needed a double click. Verified on a renamed test
  bundle with real HID clicks: five clicks in a row each switch, a shaky click switches, a release off the cell
  doesn't, a reorder is saved, the window never moves from the strip, and a drag on empty sidebar background does.

## Library (Arc 1.170, 27 Oct 2026, AX tree + window captures + 60 fps app-only recording + Swift metadata)

GitHub issue #3: Cra's Library was a separate window, so a click elsewhere sent it behind the browser, and the
Library button's hover list (downloads) and its click (the archive) showed different things.

- [O static] Arc's Library is window state, not a window: `Browser/Windows/Store/WindowState+Library.swift`, pages in
  `HomeButton/Pages/{Archive,Downloads,Media,…}`, a `HomeButton.HomeViewController` with `PageSidebarItem`s. The Library
  button is `SidebarHomeButton` (AX description "Home"). `LibraryOpenSource` = keyboardShortcut / iconTap / swipe,
  `LibraryCloseSource` = keyboardShortcut / escape / iconTap / swipe: nothing closes it on a click elsewhere.
  Window menu: View Library, View Downloads ("Opens the Downloads section of your Library."), View Easels & Notes,
  View Media, View Boosts.
- [O AX + capture, 1728×1084 window, 347 pt sidebar] the Library replaces the whole sidebar and widens it to 417 pt:
  a 113 pt page rail and the page's list. Rail buttons (AXButton, description = page name) 97×80 at x 8, 100 pt
  apart (Media 280, Downloads 380, … Archived Tabs 780 in screen y; window top 33), the group centred vertically.
  Glyph 18 pt tall from 22 pt into the button, label 12 pt semibold (white 60 %, ~82 % when chosen). The chosen page
  gets a white ~7 % fill (33,33,49 over 18,18,36) and its glyph filled in the space's accent (38,47,245 in Victor's
  JYSK theme). The rail carries a faint white wash rising toward its right edge and a 1 pt hairline (33,31,47) at
  x 112; the list sits on the plain sidebar colour.
- [O] list column: search field 36 pt tall from x 120 to 332, 10 pt below the window top ("Search Archive…",
  "Search Downloads…"), Filter button 73×36 at x 336; day headers ("Today", 13 pt semibold, x 124); rows 56 pt apart:
  24 pt icon tile at x 130, title at x 164 in 14 pt, URL under it in 12 pt. Empty Downloads page: a download glyph,
  "Nothing here yet!", "Come back after you've found some cool stuff to save."
- [O] bottom: a back arrow (32×32 at x 8, 8 pt above the bottom) leaves the Library; a gift button at x 73.
- [O] reopening shows the page last used (left on Archived Tabs, reopened on Archived Tabs).
- [O 60 fps] opening: the Library is in place within 2–3 frames, sliding in from a little to the left. Closing: it
  slides left and fades while the tab list fades back in, ~6 frames, the card edge easing from 417 to 347.
- [O live AX, Arc 1.172, 10 Nov 2026, #302] The Library is 417 pt whatever the tab sidebar's width: offline Arc
  with `sidebarWidth` 200 and 450 in StorableWindows.json, Library opened by AXPress on the sidebar's Home
  button; both read sidebar group 417, search field x 164 w 235, list scroll area x 124 w 281. So at 450 the
  Library is narrower than the tab list. Cra had added 70 pt to the user's width (`LibraryWidth` now).
- [O] Arc's narrowest window is 926 pt (split pane bars, 4 Nov), so the page always keeps at least 509 pt beside
  the 417 pt Library and Arc never has to shrink it. Cra's window goes down to 640 pt: below 926 its Library gives
  way so the page keeps 509, down to 320 pt (a 207 pt list), and follows the window while it resizes (franvz9, #302).
- [U] Whether Arc lets the Library's edge be dragged (not tried; Cra keeps it fixed). The open animation's exact curve.
- Cra: `LibraryView` in the sidebar (Downloads and Archived Tabs; Cra has no Media, Easels, Spaces or Boosts pages),
  `SidebarUIState.libraryPage` per window, `MainWindowController.showLibrary/closeLibrary`. The Library button and
  ⇧⌘L toggle it on the last page, ⇧⌘J opens Downloads, "View Archive" opens Archived Tabs, Esc and the back arrow
  leave. Opening it from a hidden sidebar shows the sidebar until it closes. Unlike Arc's quick slide-and-fade, the
  button and ⇧⌘L slide the Library in and out on the swipe's spring when the sidebar is docked (Victor, 2 Nov 2026;
  see "Swiping into the Library" below); a second press mid-slide turns it around at its current speed.

## A tab open in two windows (Arc 1.170, 27 Oct 2026, Swift metadata)

GitHub issue #4: opening in window B a tab that window A shows left A with no tab selected.

- [O static] Arc moves the page ("reparenting", `SharedWindowFeature/WindowData+ContentReparenting.swift`,
  `reparentWindowContent(for:from:to:trigger:)`, `ReparentingTrigger` = targeted / untargeted,
  `ReparentingMode` = shallow / deep, feature flags `global-window-content-reparenting-enabled` and
  `reparented-window-content-placeholders-enabled`). The window that lost the page keeps a placeholder:
  `ContentPlaceholderClient` (registerPlaceholder, placeholderSnapshots; `Placeholder` has data and sidebarItemID),
  `ContentSnapshotClient`, `BlurredItemContent` (item, image, colorScheme), `BlurredSnapshotView`, a
  "BlurredBackground" colour asset.
- [U] not observed live (two Arc windows need keyboard focus): the blur radius, whether text sits on the
  placeholder, and exactly when the untargeted reparent fires.
- Cra: both windows keep the tab selected (SidebarStore no longer clears the other window's selection). The window
  in use holds the page; another window that has the tab open shows a blurred copy of its last snapshot
  (`PaneCardView.elsewhereSnapshot`, the tab switcher's thumbnail) and takes the page back when it becomes key or
  main. Windows restored at launch leave the page to the window in use, else the first one. Verified on a renamed
  test bundle with two windows on the same tab: page and blur swap each time the other window becomes main.

### Folder icon picker (7 Nov 2026, user-supplied Arc captures)
- [O] A regular folder's context menu has Change Icon… before Rename…. Its popover points to the
  folder glyph and shows the title Icon, a trash button, and 24 glyphs in three rows of eight.
  There are no Emoji tab, search field or category bar. The current glyph has a rounded highlight.
- [O] Row order: star, bookmark, heart, lightning, triangle, asterisk, bell, lightbulb;
  chat, people, tools, egg, circle, moon, planet, leaf;
  cloud, paw, cutlery, airplane, music, video, code, skull.
- Cra: a 272 × 144 pt transient popover, 31 pt cell pitch, using the space picker's existing
  spacing. These dimensions are inferred from the supplied captures. Picking or removing a glyph
  saves `SidebarItem.folderSymbol` and closes the popover; `folderIcon` keeps the color as before.
  The symbol is a key of its own so `folderIcon` stays a string: Cra 0.1.35 fails the whole
  sidebar.json on any other type there and starts with an empty sidebar (checked 8 Nov 2026).
  Symbols use the existing `FolderEmblem` renderer, including its front-panel transform and tint;
  GitHub and GitLab live folders keep their source marks. The glyphs are Ionicons, also present in Arc's
  `ARCClients_Icons.bundle/Contents/Resources/ionicons.ttf`; SF Symbols have different silhouettes.
  Cra bundles that Ionicons font in `resources/fonts/Ionicons.ttf` (264,432 bytes, SHA-256
  `97087b7a242d8a246ee02c556da9ee0a904e04004b203ff91c4013294604709a`). Its MIT license ships in
  `resources/licenses/Ionicons.txt`. CoreText loads the bundled font directly, without system registration.
  All 24 symbols use a 16 pt font, centered by the attributed string's measured size inside a 16 × 16 pt
  unflipped `NSImage` drawing handler, then marked as template images. The picker fits them in a 14 pt square.
  The removal button uses Feather's `trash` SVG from v4.29.2 in a 16 pt square;
  its MIT license ships in `resources/licenses/Feather.txt`.
  Arc's `ionicons.ttf` is a Fontello build (name table: "Generated by svg2ttf from Fontello project"),
  1181 glyphs named as in Ionicons 5 (`chatbubble-ellipses`, `ellipse-sharp`, `restaurant`); it
  matches no Ionicons 2.x–4.x release on npm (checked 8 Nov 2026).
- [O static, installed Arc, ARM64] Swift reflection identifies `FolderIcon.FolderIconView.customIconImage`
  and `_customIconLayer`. The image setter (`0x101673efc` → `0x101673c90`) updates the layer at the
  field offset stored in `0x104642d80`. The layout routine (`0x101674994`) uses that same offset at
  `0x101674f80`, computes `min(front.bounds.width, front.bounds.height) - 2.5` at `0x101674fc0`–
  `0x101674fe8`, centers the square, and calls `setFrame:` at `0x101675004` (selector in `0x104548cc8`).
  This is 9.5 × 9.5 pt for the 16 × 12 pt front panel, including live folder images. Cra applies
  the same formula in `FolderGlyphView.layoutEmblem`; an explicit relative size still overrides it.
- [O static, installed Arc, ARM64] The custom layer is `ARCUI.TintableImageLayer` (descriptor
  `0x103d52f60`), with `image`, a lazy `maskLayer`, and `tintColor`. Its image update
  (`0x1009bf9d0`) obtains a CGImage at `0x1009bfa80`, assigns it to the mask's contents at
  `0x1009bfac4`, and attaches the mask at `0x1009bfb0c`. The mask uses `resizeAspect`
  (`0x1009bfd50`) and follows the layer's bounds (`0x1009bff50`). Tint sets the layer's
  background color (`0x1009bfe30`); it is not baked into a small bitmap.
- [O static, 8 Nov 2026] `CGImage` resolves to the `NSImage` Compatibility category's getter at
  `0x100ba169c`. It reads the image's width and height, constructs a zero-origin rectangle of that
  size, and calls `CGImageForProposedRect:context:hints:` at `0x100ba16dc`, with nil context and
  hints. It does not resize the source to the emblem's frame or multiply it by the backing scale.
- [O static, 8 Nov 2026] The folder's selected-icon update at `0x1003eed20` reads the requested
  source size through `0x102a86f60`, which returns the address `0x10387cd78`: a double equal to 16.
  It passes that size to the icon-to-image conversion at `0x1003eed34` → `0x100d6422c`, then calls
  the folder's `customIconImage` setter through vtable offset `0x268` at `0x1003eed54`.
  The Ionicon branch goes through `0x100d642bc` and the image cache at `0x100c2539c`.
  The font-image constructor (`0x100c255bc`) creates a square `NSImage` using the requested size
  and an unflipped drawing handler. Its drawing body (`0x100c256f0`) creates black attributed text,
  measures it with `size`, and draws at half the difference between canvas and text dimensions
  (`0x100c25794`–`0x100c257b4`). This uses text metrics rather than the visible glyph's bounding box.
- [O asset + runtime, 8 Nov 2026] `ARCClients_BaseAssets.bundle` contains `GithubFavicon`, sourced
  from `github-black.svg` / `github-white.svg`, with 32 px and 64 px renditions plus preserved vector
  data. Loading it with `Bundle.image(forResource:)` reports a 32 × 32 pt image; the getter above
  returns a 32 × 32 px CGImage with nil context. Cra's live folder SVG marks now use that 32 pt
  source canvas; their menu copies stay at 16 pt. Cra keeps the Octicons contour (MIT) on that
  canvas rather than copy Arc's SVG, which comes with no license. The GitLab canvas follows the same size.
- Cra uses the same alpha-mask and background-color composition for template emblems, keeping
  the exact centered square from the formula above. It obtains the CGImage using the image's own
  size, with nil context and hints, then fits it through Core Animation. Color changes, display-size
  changes, backing-scale changes and opening reuse the source; changing the image replaces it.
  This shared path handles all picker symbols and GitHub/GitLab live folder marks. Original-color
  emblems use the image directly with `resizeAspect`. All manually created folder layers and masks
  follow the backing scale. The earlier intermediate 32 px source was a Cra-specific choice and
  has been removed. Final visual parity still requires checking in the running app.

### Favorites grid columns and Peek (Arc 1.170, 29 Oct 2026, issue #12)
- [O live] Favorites columns by sidebar width (4 favorites; `sidebarWidth` set in StorableWindows.json with Arc
  quit, tile frames read from the AX list under `sidebarFavoritesCollectionView`): 347/300/260/230 → 4 columns
  (tiles 76/…/55/47 × 47), 227/225/220/212/205/200/170/140 → 2 columns (101/100/98/94/90/88/73/58), 100 → 1
  (84). That rule ("4, else 2, else 1, never 3") only held for exactly 4 favorites.
- [O live, Arc 1.171, 31 Oct] 1–9 favorites at widths 347/230/200/140/100 (offline copy, AX frames). Widest =
  the most columns up to 4 keeping a tile ≥ 47 pt (3 at 200, 2 at 140, 1 at 100); then the fewest columns
  that need no more rows: 1 → one full-width tile, 2 → halves, 3 → thirds, 5 → 3 + 2, 6 → 3 × 2, 7 → 4 + 3,
  9 → 3 × 3; 4 at 200 → 2 × 2. A short last row keeps the tile width, left-aligned. Tile x is rounded to the
  half point (84.75 → 85, 254.25 → 254.5); widths are not. Cra (`FavoritesGridView.columns(forWidth:)`)
  matches all 41 measured cases exactly.
- [O static] Peek is a Little Arc presented modally (`littleWindowViewController`, `presentModally`,
  `modalState`, `peekedModalControlsAlternateOrderEnabled`). Links ▸ "Open a Peek window when clicking on links to
  other sites" (note: "This only affects Favorites and Pinned tabs"; key `modalEnabled`) and "Open a Peek window
  when clicking on links with Shift held" (`shiftClickModalEntryPointEnabled`); "Exit the current context. Such
  as closing a Peek window"; "Undo prompt for re-opening a closed Peek". Not seen live (needs a real click).
- Cra: a Little Window docked over the page area (6 %/5 % inset), a 25 % black shade over the browser window
  that closes it on click, Escape the page didn't use closes it, "Open in <space>" makes it a tab. Same site =
  registrable domain (`SiteKey`). Verified on a test bundle with a CDP click in a favorite: Peek opened, the tab
  stayed, promote and ⌘W worked.

### Favorites per profile (Arc 1.171, 3 Nov 2026, offline Arc, issue #154)
Offline Arc (fake home with Arc's own second profile "Work" = Profile 1, see "One space") with spaces Personal and
Side on Default (topApps: Mail, Music, News) and Work on Profile 1 (topApps: Jira). Space switches through
Spaces ▸ <space> (AX), profile changes through Spaces ▸ Change Profile (the sheet's picker is a SwiftUI menu: one HID
click, then AX), 120 fps region recordings.
- [O] AX: `sidebarFavoritesCollectionView` (347×63) is its own list above the 3 × 347 pt pager of space pages.
- [O live] Personal → Side (same profile): header and list slide, the tiles stay still in every frame. Side → Work
  (other profile): the tiles slide out with the page and Work's slide in.
- [O live] The open tab is per space: Mail opened in Personal, Side still showed its own (nothing), Music opened in
  Side; each space came back to its own.
- [O live] Change Profile: the space shows the new profile's list, nothing moves. With Personal and Side both on Work,
  StorableSidebar kept Default's topApps container with all three; Personal back on Default showed them again, Mail
  still highlighted. A favorite open in the space stays on screen (same page, title) after the change, its tile gone.
- [O live] A favorite's menu: Copy Link, Share ›, Change Icon…, Rename…, Mute, Edit Pinned Page ›, Open in Split View
  (Add Split View while open), Duplicate, Move to › Profile › ✓Default / Work, (Close Tab ⌘W while open), Remove
  Favorite. Remove Favorite deletes it: not in any space's pinned or Today list, not in StorableArchive.
- Cra (`FavoritesSharing`, `SidebarDocument.profileFavorites`): with the setting on, each profile has a list
  (container kind `.favorites(spaceID: sharedFavoritesSpaceID)`) that its spaces point at and that outlives them;
  a favorite loads in its list's profile; turning it on merges the spaces' own favorites into their profile's list
  (a page twice once), off gives each space its own copy. Tile menu: Remove Favorite, Move to › Profile.
  SpacePagerView holds the tiles still between two pages that show one list.

### Reordering Favorites (Arc 1.171, 4 Nov 2026, offline Arc, issue #176)
- [O static] The top apps are an NSCollectionView (`AppTrayViewController`, `AppTrayCollectionViewLayout`) with the
  collection view's drag delegate (`validateDrop:proposedIndexPath:`, `layoutAttributesForInterItemGapBeforeIndexPath:`).
- [O live] Offline Arc, 4 favorites at 347 pt, real HID drags, AX tile frames read mid-drag, 60 fps recording. A dragged
  favorite leaves the flow: the others close up and the slot under the pointer stays open (over News: News moves to
  slot 0, slot 1 open; over Maps: News, Docs, Maps, slot 3 open). The tiles slide over ~0.15 s, fast at first. The
  image under the pointer is a light card (white at about two thirds over the sidebar), the tile's corners, a soft
  shadow. Dragged down off the tiles over the space header the slot stays open and no "Add to Favorites" shows.
  Released over Maps' slot: News, Docs, Maps, Music.
- [O live] A Today tab dragged over the tiles opens a slot at once and the grid relays out for five (3 + 2, a second
  row, the header moves down). Released over the second slot: News, Today P, Docs, Maps, Music.
- Cra: `FavoritesGridView` is the drop target (the tiles no longer are), `FavoritesLayout.slot(at:)` /
  `slot(ofTile:opening:)` place the open slot, `SidebarStore.addToFavorites(_:in:at:)` inserts a tab there. The
  same drags on a test copy give the same orders and frames.

### Splits in Favorites (Arc 1.171, 31 Oct 2026, Swift metadata + offline Arc)
Request from a Cra user (DM, 31 Oct): "the split tabs being pinned, I also need them pinned at the top".
- [O static] A top-apps item can be a split: `AppTray…ViewState.AppItem { childItems: OrderedDictionary<id,
  ChildItem { defaultIconType, highFidelityIconMatchingURL }>, layoutOrientation: horizontal|vertical, isSelected,
  isHighlighted, … }`, drawn by `AppTrayItemViewAppKit` with one `AppTrayChildItemView` per pane (own isHovered /
  isSelected / subtitle / badge) and cut by `AppTrayItemMaskShape { numberOfItems, cornerRadius, lineWidth,
  isReversed, layoutOrientation }`; per-cell rects with their own rounded corners (`AppTrayItemLayout.ItemLayout`).
- [O live] Offline Arc (fake home, see "One space") with a horizontal and a vertical split in StorableSidebar's
  topApps container (`splitView` items, children = panes): one tile per split, the same size as a page's tile,
  cut by a 2 pt gap (4 px at 2x) along the split's axis — side by side, or stacked for a vertical split. Outer
  corners stay rounded, the cut's corners are square. Hover darkens the whole tile, not one cell. Clicking a cell
  opens the split; the open split's tile is ONE selected tile with no cut (uniform 240/239/232 on a light theme).
- Cra: favorites hold splits (`SidebarStore.addToFavorites` lifts a pane to its split, `removeFromFavorites` too),
  `FavoriteTileModel.cells` + `FavoriteTileMetrics.cut` (an even-odd mask, dropped while the split is open), a
  click opens the split on the pressed pane, the tooltip names the hovered pane, the menu is the split row's with
  "Remove from Favorites" first. Not seen in Arc: the open split's icons (offline Arc had no favicons).

### Folder previews (Arc 1.171, 31 Oct 2026, Swift metadata + offline Arc, 120 fps recordings)
- [O static] `Previews.FolderPreviewState { itemID, title, allPossibleChildren: [FolderPreviewItem] }`,
  `FolderPreviewItem { sidebarItem, title, url, faviconType, lastVisitDate, isBadged }`,
  `Arc.FolderPreviewView { searchQuery, selectedItemID, contentViewHeight }` in an in-window
  `FolderPreviewHostView` with an event monitor; `FolderPreviewAction = onSelectChildItem(index, resultsCount,
  modifiers, searchQuery) | contextMenu(copyURL, openInSplitView, duplicate, archive) | onAppear | onEscape |
  onLeftMouseDownOutOfFrame`. Shown by `SidebarPreviewHoverTracker` (`showPreviewTask`); settings key
  `folderPreviewEnabled`, one of the "Show Arc Previews:" toggles ("Hover your mouse over an Arc Folder, Pinned,
  or Favorited tab…").
- [O live] Only a CLOSED folder previews (an open one shows nothing). Rows = every tab under it, nested folders
  included, newest `lastVisitDate` first, subtitle "31 minutes ago" / "15 hours ago" / "1 week ago" / "1 month
  ago"; the first row is highlighted and the field already has the caret ("Search Tools…"). Typing filters
  (title/URL), the panel keeps its height; nothing found: "No tabs matching that search 🤔", 13 pt, centred,
  wrapped so the emoji takes a second line. Escape closes. The pointer's row gets the same fill as the
  keyboard's row, both at once (hover doesn't move the selection). Moving onto another folder switches.
- [O live] Timing: the folder row turns hovered, the preview starts 0.45 s later and is in after ~90 ms (opacity
  plus scale from ~0.85 about the middle of its left edge); leaving folder and preview fades it out within
  ~40 ms over ~80 ms.
- [O live] Geometry (2x captures, sidebar 300): 240 pt wide, 4 pt right of the sidebar, centred on the folder
  row and kept 18 pt inside the window (so a folder near the top gets a preview at y 18); height
  53 + 45 × rows, at most 320 (6+ rows scroll; one row = 98). 10 pt corners, 0.5 pt grey (~58) outline and a 0.5 pt
  white-20 % line inside it. Search area 48 pt (11.5 pt magnifier centred 20 pt in, 13 pt text from x 36,
  placeholder white ~58 %), 1 pt white-13 % hairline, rows from 4 pt below it on a 45 pt pitch, fill 44 pt tall,
  4 pt in from each side, 4 pt corners, white ~7.5 %; 16 pt favicon centred 20 pt in, title 13 pt regular
  (white ~85 %) and age 11 pt (white ~55 %) from x 36. Always dark, whatever the space theme: a blur that lets
  ~12 % of the backdrop through (23/23/23 over a dark page, 45/44/36 over a light yellow one) — a page icon
  under it did not show through.
- Cra: `UI/Sidebar/FolderPreview.swift` (a child panel, since pages are CEF child windows; hudWindow dark +
  rgb 17 @ 77 % over it), hooked from `SpaceListView.hoverAt`, Settings ▸ Tabs "Preview a folder’s tabs when
  hovering over it" (`AppSettings.folderPreviews`), a floating sidebar stays out while it is up, and
  `cra://debug?folderPreview=<folder id>` opens it for screenshots. Text widths, baselines, hairline and
  magnifier match Arc's to the pixel at 2x. Left as Cra's choice: typing or arrowing keeps it open after the
  pointer leaves (not observed in Arc); picking a tab in a closed folder leaves the folder closed without
  showing the tab under it (Arc keeps a closed folder's open tab visible; Cra's 29 Oct work on that isn't on main).

## Solid themes, list scroller, now playing, many spaces (Arc 1.171, 31 Oct 2026, offline Arc, issues #28 #30–#33)

Offline Arc as in "One space", with these extra traps: Arc wipes a hand-built StorableSidebar.json (first-run
"Space 1") when there is no StorableWindows.json, or when `firebaseSyncState.syncHealthStatus` is `healthy`
(it syncs and empties the spaces); reuse the sync states from a file Arc itself wrote offline (`notWorking`).
Arc's menus are disabled while it is in the background: activate it by pid (`open -a` starts the real Arc).
Theme palettes in a hand-built space can be borrowed; only the `background` style was measured.

**Captures on the built-in display are Display P3.** A solid sRGB colour reads back P3-encoded (cyan #33B2CC →
~#5BB0C9), so convert before comparing with sRGB colours; compare Cra and Arc through the same pipeline.

- [O] Solid colour (`blendedSingleColor`): flat, the same with `isVibrant` true or false and with light or dark
  `contentOverBackgroundAppearance`. Over solid white and black backdrops, nine colours, in sRGB: active =
  α·colour + (1 − α)·(66 + 0.52·backdrop), inactive = α·colour + (1 − α)·212 (flat), α = 0.19 + 0.55·intensity
  (0.191 / 0.459 / 0.742 at 0 / 0.5 / 1), within 3/255. Cra (`SpaceTheme.solid`, `ShellView.solidBackdrop`: dim
  0.30, lift 0.26; inactive dim 1, lift 0.83) matches all 22 test spaces within 2/255 over both backdrops, except
  intensity 0 over white (19/255 light). A space with no `windowTheme` is Arc's default dark purple; the import
  uses Ink instead of the next preset.
- [O] Sidebar backdrop through activation and fullscreen (2 Nov 2026, issue #83; Arc 1.171, 1x external display,
  ~56 fps `screencapture -v` recordings, a probe app with Cra's layer next to NSVisualEffectView panels over a
  6 pt stripe window). Arc's sidebar is an NSVisualEffectView (`behindWindowBlurView`). Its layer tree, dumped
  from a probe: inactive = no CABackdropLayer at all, an opaque fill; active windowed = a CABackdropLayer with
  `allowsSubstituteColor` 1 (Cra's had 0); active fullscreen = the backdrop removed and a `CAChameleonLayer`
  "desktop tint" at opacity 1 in its place, with the same filters as the blur (hudWindow: sdrNormalize,
  colorSaturate 1.6). In fullscreen there is nothing behind the window, so Cra's capture read black: black at
  intensity 1 sat at 17/17/17, NSVisualEffectView over the same wallpaper at 130/102/84, raw tint 186/156/135.
  Victor's light vibrant theme fullscreen, same display and wallpaper: Arc 207/169/112 (top) … 215/161/105,
  Cra before 69/64/47 … 78/66/47, Cra with the tint 192/176/129 … 207/171/123 (Arc saturates the tint, Cra's
  untinted blur path doesn't). A capture that isn't live (probe: `windowServerAware` off) shows the window behind
  sharp and legible; the same layer with `allowsSubstituteColor` draws a flat fill instead. Arc switches active ↔
  inactive in one frame, no fade. Cra: `ShellView` allows the substitute colour and swaps in the desktop tint while
  the window is fullscreen; `cra.log` notes each change ("sidebar backdrop: desktop tint, active"). Cra before the
  change kept a stale, hard-edged backdrop for seconds after launch and activation in 2 of 3 runs, the changed
  build in none of 3 (other sessions' windows moved between runs, so take that as a hint). Not seen here: the
  sharp sidebar on activation from Mission Control, Finder or a fullscreen Space (1x displays).
  `screencapture` stills are no use for this: they disagreed with recordings of the same state.
- [O] Follow-up (3 Nov 2026, issue #132: on another Mac the fullscreen solid sidebar rested ~60 levels darker than
  Arc in the same space). NSVisualEffectView's hudWindow tree, dumped from a probe: windowed active = backdrop
  (sdrNormalize, gaussianBlur 30, colorSaturate 1.6, `scale` 0.125, `substituteColor` nil: the window server picks
  the substitute) + fill + tone + the `CAChameleonLayer` at opacity 0.05; fullscreen = the backdrop REMOVED from
  the tree, the chameleon first at opacity 1 with `[sdrNormalize, colorSaturate 1.6]` and no blur. CAChameleonLayer
  has no properties of its own. Cra's tint was bare (no filters) and its blur only hidden. On this Mac's SDR
  displays a bare chameleon already resolves the wallpaper (194/166/146; with the filters 209/163/131) and a hidden
  blur beside it changes nothing, so the dark rest did not reproduce; the filters are the one difference left
  against Arc's layer, and `sdrNormalize` is the EDR-display step. Cra now builds the tint with those filters and
  keeps only the layer it draws from in the tree, like AppKit (none while inactive, under the opaque fill).
  CloudDev (#F25E6B, 0.8) fullscreen, stills: 214/116/119 before, 217/114/117 after (Arc on #132's Mac 210/110/117).
  A Space swipe reads the inactive value until the app is active again, then steps in one frame, as AppKit's
  material does (`followsWindowActiveState`).
- [O] Reduce Transparency (3 Nov 2026, issue #156, the reporter's 0.1.28 recordings next to Arc's, 60 fps). On the
  reporter's Mac Arc's sidebar never passes the backdrop: flat in every frame, windowed or fullscreen, active or not,
  over a wallpaper Cra's blur shows plainly (white 0.8 space 218–222 grey; CloudDev #F25E6B 0.8 210/110/117 windowed
  and fullscreen alike; hidden-sidebar panel 156/64/72). Cra in the same captures: blur active, 231/127/135 flat
  inactive, 169/74/82 over the desktop tint in fullscreen, so every activation and every Space swipe stepped and Arc's
  never did. That is Accessibility ▸ Display ▸ Reduce transparency (or Increase contrast, which turns it on):
  NSVisualEffectView, dumped from a probe with `NSWorkspace.accessibilityDisplayShouldReduceTransparency` swapped to
  true and `_accessibilityRTChanged:` sent, drops the CABackdropLayer and the CAChameleonLayer and keeps one opaque
  fill (hudWindow aqua 228 active / 240 inactive, dark 38 / 40; sidebar and underWindowBackground aqua 246 / 236, dark
  56 / 20). ArcCore also reads the setting itself (one ObjC helper at 0x457c2d4 in 1.171's arm64 slice). Solving
  α·colour + (1 − α)·F, α = solidAlpha(0.8) = 0.63, gives F ≈ 160 for Arc's pinned sidebar in both spaces (against
  212 inactive), and ≈ 40 for its floating panel (the dark material's fill). Cra's own CABackdropLayer ignored the
  setting. Cra now resolves the layer through `SidebarBackdrop` (CraCore): with Reduce transparency there is no
  capture at all, solid themes rest at dim 1, lift 0.63 active or inactive (Arc's value doesn't move when its
  fullscreen swipe lands, Cra's stepped from the inactive 212), light vibrant themes at their inactive look, and the floating sidebar drops its white lift so the
  dark material's fill shows under the colour like Arc's panel (Cra pinned − floating 45/46/45, Arc 54/46/45); cra.log adds ", reduce transparency" and the diagnostics export names the setting.
- [O] Activation and fullscreen with Reduce transparency off (4 Nov 2026, issue #156 on 0.1.29; built-in XDR display,
  120 fps ScreenCaptureKit samples; a probe window with a hudWindow NSVisualEffectView beside a copy of ShellView's
  backdrop logic, logging both layer trees every 4 ms; an offline Arc 1.171; a Cra test copy with a solid #F25E6B 0.8
  space). AppKit's material follows its window, not the app: minimizing goes flat as the window resigns main/key, while
  the app is still active, and a restore from the Dock while another app is active keeps the opaque fill through the
  genie until the window is main again, 0.41 s after `didBecomeActive`. Cra followed the app, so it re-inserted the live
  capture at activation, 0.43 s before the window had landed. That's a capture of a window still flying out of the Dock:
  the reporter's matte (substitute colour) or sharp frames on restore. Cra now uses `SidebarBackdrop.windowActive`: app
  active, not miniaturized, and the key or main window is this window or one of its child windows (page, DevTools).
  Measured after the change: Dock restore active at +0.46 s (before: +0.03 s), minimize flat at once, plain activations
  unchanged (one step at +0.03 s), the command bar's panel keeps the sidebar active. Not reproduced here: a dropout on
  a plain activation (Arc, AppKit and Cra all switch in one frame, no matte or sharp frame). Fullscreen: AppKit swaps the
  capture for the desktop tint at `willEnterFullScreen`, the same frame as Cra; Arc's sidebar jumps at the start of the
  zoom (16/12/31 → 41/33/50 on its default theme) and steps ~2 levels when the Space settles (45/30/43 → 43/30/45), and
  Cra does the same (189/112/120 → 216/133/137 at the start, 220/124/123 → 218/124/126 at the end), so no fullscreen
  difference against Arc reproduced on this Mac.
- [O] Space switches, Stage Manager and AppKit's capture settings (5 Nov 2026, issue #156 on 0.1.30; built-in XDR
  display; a probe app with a hudWindow NSVisualEffectView logging every 4 ms and on each notification: app active,
  key, main, `NSWindow._hasActiveAppearance`, the view's `_shouldUseActiveAppearance` and its layer tree; ⌃← / ⌃→
  posted as HID events). A full screen window keeps its active appearance when its Space slides away: the app resigns
  active and the window loses key and main, but `_hasActiveAppearance` and the material stay active, the desktop tint
  at opacity 1 throughout. So Arc's sidebar never leaves its active look on a ⌃← / ⌃→ round trip, while Cra's rule (app
  active and key or main) went to the flat fill and came back at `didBecomeActive`, ~4 ms after the Space change, which
  is after the slide: the reporter's lighter frames, ~5 frames past the animation. Windowed, the material goes inactive
  as the window resigns main, as before. AppKit tells its views through `-[NSView _windowChangedKeyState]`. Cra now asks
  a zero-size NSVisualEffectView that follows its window (`ActiveAppearanceProbe`) and ORs that answer into
  `SidebarBackdrop.windowActive`. The rule's own half stays, because AppKit's answer doesn't count Cra's page windows.
  Layer dump of the windowed hudWindow material: `CABackdropLayer` scale 0.125, `windowServerAware`, group
  `NSCGSWindowBehindWindowCaptureBackdropGroup`, `allowsSubstituteColor` 1, `substituteColor` nil, filters
  `sdrNormalize`, `gaussianBlur` (radius 30, normalize edges), `colorSaturate` 1.6; then the fill (0.157 grey at 0.4),
  the tone (0.08 grey, lighten) and the `CAChameleonLayer` at 0.05. Inactive it drops only the capture, the fill and
  tone go opaque, and the chameleon stays in at 0.05. Side by side over a stripe window, AppKit's settings on a bare
  layer blur like the material and Cra's full-scale 40 pt blur spread a 20 pt band about twice as wide and greyer. Cra
  now builds the capture with AppKit's settings (an eighth of the pixels for the window server to rebuild when a window
  comes back, the dropout the reporter saw out of Stage Manager on an M1) and keeps the desktop tint in the tree at 0.05
  under the capture, at 1 in full screen, out only with Reduce transparency. Stage Manager itself was not tested here.
- [O] Tab list scroller: AppKit overlay scroller (AXScrollBar, 17 pt track) shown while scrolling, then faded;
  the knob is 4 pt wide, 3 pt in from the sidebar edge, white 49 % on a dark theme, no track. Cra:
  `SidebarScroller`, 10 pt wide so it stays in the gutter right of the rows (knob on Arc's exact columns).
- [O] Same list with "Show scroll bars: Always" (1 Nov 2026, Arc launched with `-AppleShowScrollBars Always`,
  issue #48): Arc follows the system (its binary reads `preferredScrollerStyle`, never sets a style; own
  `NoBackgroundScroller`) to a legacy scroller, always shown while the list overflows, no track. AX: a 10 pt
  AXScrollBar, knob indicator = AppKit's legacy knob rect (3 pt in from the scroller's top and bottom, 237.5 pt
  for 415 of 716). Pixels: the knob is 5 pt wide, 3 pt in from the sidebar edge, 1 pt inside its knob rect at
  both ends, 134/132/141 over 14/10/28 (white 50 %, the same as AppKit's own dark legacy knob; its light one is
  black 50 %). The rows give up 8 pt (selected fill's right end 8 → 16 pt from the edge, outline 349 → 341 wide).
  Cra: no forced overlay (it hid the knob: AppKit keeps an overlay knob at alpha 0 while the system prefers
  legacy), `SidebarScroller` draws that knob in legacy style and `SpaceListView.rowsWidth` drops 8 pt.
- [O] Playing tab row: `speaker.wave.3` between favicon and title (17.5 pt wide, 11.5 tall, title 8 pt after
  it), white ~60 % on a dark theme (the glyph tone, not the title's colour).
- [S] Now playing is Arc's `MediaControlsFeature` (ArcCore-free, in the Arc executable): SwiftUI `MiniPlayerView`s in
  a `MediaControlsHostingView`, fed by Chromium's media session (`webContents:didChangeMediaSessionState:`). Swift
  field metadata: `MiniPlayerFeature.State` {title, icon {image, tintColor}, volume: Double, isTabMuted,
  isBackToPIPButtonEnabled, tabURL, isVolumeExpanded, mediaType = audioVideo {mediaSessionStatus, hasNextTrack,
  hasPreviousTrack} | recording {canToggleMicrophone/Camera, isMicrophoneOn/CameraOn}}; view actions setVolume,
  setIsPaused, toggleVolumeDrawer, backToTabClicked, titleRowClicked, controlsRowClicked, playNext/PreviousTrack,
  closeButtonClicked, toggleMuted, toggleCamera/Microphone, backToPipClicked; `MediaControlsData.maxActiveMediaControls`;
  per-card view state {height, opacity, yOffset, widthOffset}; `MiniPlayerView` reads colorPalette + colorScheme;
  marquee titles behind `miniPlayerMarqueeTitleEnabled`. Asset catalog `ARC_MediaControlsFeature.bundle`: one colour,
  `PlaybackControlForeground` = black 50 % (light) / white 66 % (dark). Long strings: "Close Mini Player", "Open
  Picture in Picture", "Adjust Tab Volume", "Toggle Microphone"; symbols backward/forward.end.fill,
  speaker.wave.3.fill / speaker.wave.1.fill, video.slash.fill (short ones are inline, read live instead).
- [O] Now playing, live: a card appears for an audio tab once it is off screen (a video in Picture in Picture has
  none). Cards 8 pt in, bottom where the list ends (50 pt above the window bottom), 6 pt corners, filled with the
  palette's `backgroundExtra` for the space's scheme: dark = 15 % of `shadedDark` (#110D00 for #6F5600), light =
  near-white (#FEFDFC); title white ~81 % / black ~85 %; disabled glyphs a third of the foreground; hover square
  24 × 23 pt, white 7 % / black 8 %; favicon placeholder foreground ~15 %. Rest: newest card only, 33 pt: favicon,
  previous, play/pause, next, volume, laid out like an HStack (glyphs 16 / 13 / 8.5 / 13 / 19 pt, equal gaps,
  14 pt in on the left, 12.5 on the right); up to two more peek out, each 7 pt higher, 5 pt narrower a side and
  0.2 fainter, the second showing the tops of its controls at ~15 % (raised 7.25 pt). Hover: all cards 65.5 pt,
  title row (tab title, 13 pt, 14.5 pt in, centred 16.25 pt from the top; Picture in Picture glyph 15.5 pt wide
  centred 45.5 pt from the right on video tabs; ✕ 11 pt centred 21.75 pt from the right), stacked upward 5 pt
  apart, oldest on top, ~0.2 s ease-out both ways (collapse starts at once). Tooltips: "Back to Tab", "Previous
  Track", "Pause"/"Play", "Next Track", "Adjust Tab Volume", "Open Picture in Picture", "Close Mini Player";
  disabled previous/next (no media session handler) have neither tooltip nor hover; the title row has neither.
  Volume opens a drawer: the card grows 33 pt (bottom fixed) with a slider centred 16.25 pt from the bottom: 6 pt
  rounded track 8 pt in, filled = palette tintedLight (dark) / shadedDark (light), empty = white 10 % / black 18 %,
  knob 20 × 16 pt pill, #DBDBD9 (dark) / white with a soft shadow (light); the volume button stays lit; the glyph
  shows 3 waves, 1 wave (seen at 27 % and 45 %), none at 0. Pause keeps the card (▶); ✕ removes it. Cra:
  `NowPlaying` + `NowPlayingTrayView` (verified side by side in both schemes, glyph boxes within 1 px); controls
  run the page's media session handlers (captured by `PageScript`) or its media elements; volume sets the page's
  media volume. Not built: the recording card (mic/camera) and marquee titles.
- [O] Space dock with many spaces (5, 7, 8, 12, 16, 22 spaces): cells share the 217 pt between Library and +
  (300 pt sidebar) in half points, at most 34; below 22 pt the open space keeps 22 and the others split the
  rest (17.5 / 13 / 9 pt with 12 / 16 / 22 spaces).
- [O] Space dock dots (Arc 1.171, 8 Nov 2026, #252; offline Arc with 4 and 12 spaces, 2x window captures,
  light #CDB68F and dark #2A2536 sidebars): a space with no icon (`customInfo.iconType` absent, Remove Icon) is
  an 8 pt dot centred in its cell, level with the + glyph. Ink: black on light, white on dark, 0.5 for the open
  space, 0.25 (light) / 0.18 (dark) for the rest. Squeezed (cells under 22 pt), every space but the open one is
  a 4 pt dot in the same ink, emoji spaces too; the open space keeps its emoji, or its 8 pt dot.
- [O] Hover in a squeezed dock (Arc 1.171, 10 Nov 2026, #252; offline Arc with 12 spaces, real pointer, window
  captures and a recording): the hovered space takes the 22 pt cell (the others close up to 17.5) and shows its
  emoji in full colour, or an icon-less space its 8 pt dot at the open ink (0.5); the open space shrinks to a
  4 pt dot at the others' ink (0.25 light / 0.18 dark) until the pointer leaves. No hover fill (a dock with room
  keeps its fill). The swap takes ~0.2 s: cells slide, the hovered emoji grows in from small while the open
  one fades to its dot. The usual tooltip (name + ⌘n) shows above. Cra: `SpaceDock.wide` / `isLit`, the cells
  slide and cross-fade over 0.2 s (no grow), pinned by the space-dots-hover scenario. Cra: CraCore `SpaceDock` (widths, `mark`, `dotAlpha`), drawn by `SpaceCellView`; the Arc
  importer keeps an icon-less space icon-less (it used to get 🗂️). Pinned by the space-dots and solid-spaces
  scenarios.

## Developer bar (Arc 1.170, 1 Nov 2026, issue #42, live window captures at 2x)

Arc's toolbar module ContentPanel carries `ContentPanelTextField`/`ContentPanelTextView` (the in-place
address field) and `Stripes`/`StripesConfig` (drawn in code; `StripeIcon` in Assets.car is the payment
company's logo). Measured on example.com (a developer host) in the JYSK space, captures in Display P3,
converted to sRGB where noted:

- Height 40 pt (80 px) against 32 for the normal bar; a 1 pt rule along the bottom, white ~10% over the fill.
- Fill: not the page's theme-color. JYSK's bar is P3 62/67/202 = sRGB 61/67/210, which is Arc's semantic
  dark `focus` colour (0.294, 0.329, 1.021, α 0.8075, from StorableSidebar.json) over black. Cra derives
  it from the accent (SpaceTheme.developerBarColor: OKLab L 0.552 at the sRGB chroma edge × 0.8075) and
  lands at 44/72/206 for JYSK: Arc's palette hues drift from the base colour's (+5.6° for JYSK, +1.6° for
  Victor), so one more space would be needed to model that.
- Stripes: white ~2% bands at 45° running down to the right, 21 pt wide along the bar every 45 pt; at the
  bar's top the first band starts 14.5 pt from its left edge.
- Ink: icons and the lock P3 236/237/254 (Arc's foregroundPrimary), URL text the same antialiased.
  Dividers P3 93/99/230 = foregroundSecondary (131/137/255) at ~45%.
- Icon hover: a 28 × 28 pt rounded rect (radius ~5–6 pt), centred in the bar, white 8%. The URL has no hover.
- Click on the URL: the full URL becomes editable in place (same monospaced text), all of it selected;
  selection P3 111/117/251 (foregroundSecondary at ~60%), text 226/227/254, and the whole bar lifts by a
  white ~9% veil while editing. One Esc left it editing (it may only revert the text); Cra ends the edit.
- Arc's developer bar also has buttons Cra doesn't: Capture, Screenshot | DevTools, Network, Inspect |
  extensions … Split View, with dividers between the groups.

DevTools in Cra: Chrome picks the frontend URL (DevToolsClient::OnBeforeBrowse never sees the first
navigation), so the dockable `can_dock=true` load now replaces it at the first OnLoadStart instead of
after OnLoadEnd: open → page bounds 185–200 ms instead of 265–290 ms. A click inside DevTools makes its
child window key; AppKit then spent the next toolbar click on making the main window key, so toolbar
buttons accept first mouse while a child window is key. Clicks after the page had focus were not affected
(real HID test).

## Toolbar clicks, developer bar buttons, developer-mode rows (Arc 1.170, 2 Nov 2026, issue #88)

AX reads of Arc's windows, 1x window captures, and HID clicks while the Mac was idle:

- [O] Normal bar address: `example.org/cra88/deep/path?q=1` showed host bright and path + query dim, but
  only because Victor's Arc has **Show Full URL** on (`toolbarShowFullURLsEnabledPreference = 1`; the
  reporter's screenshots, Arc's default, show `github.com` alone). The option is on the address's
  right-click menu as "Show Full URL" / "Hide Full URL" (ArcCore strings, with "Copy URL" and "Hide
  Toolbar"). Cra: `AppSettings.toolbarShowsFullURL`, off; the Arc import takes Arc's preference.
- [O] The link glyph before the address is a button of its own, "Copy Current URL", 24 x 24 pt; the
  address text starts 27 pt after the button's left edge (AX frames). Hovering the address lights a
  24 pt pill around the host only, 7 pt either side of the text, starting about 20 pt into the copy
  button's box (reporter's 2x capture: glyph 14 pt at 34-48 pt, pill 49.75-132.5 pt, text 56.5-126 pt;
  pill 86/86/86 on a 65/65/65 bar). Cra's ToolbarURLButton draws the two fills itself and gives the
  4 pt where they meet to the copy box.
- [O] Clicks: empty bar space left or right of the address opens nothing (window keyed by a page click
  first, two runs, captures); the address opens the command bar; a click on the address while the bar
  is open closes it and it stays closed; the next click opens it. Cra: PaneToolbarView only focuses its
  pane on empty space; `DismissingClick` keeps the closing click from reopening the bar.
- [O] Developer bar (AX descriptions, left to right): Site Settings (28 pt), `contentPanelTextField`
  from 40 pt to 7 pt before Copy Link (530 of 923 pt), Copy Link | Capture Window, Capture | Toggle
  Console, Toggle Network Panel, Inspect Element | Extensions Menu, pinned extensions, Split View Menu.
  Buttons 28 pt edge to edge; rules 1 pt: copy, 14, rule, 13, Capture Window; Capture, 8, rule, 8,
  Console; Inspect, 7, rule, 8, Extensions. Glyphs: terminal, globe, crosshair.
- [S] ArcCore names Chrome's commands (`DevTools_ToggleConsole`, `DevTools_InspectElement`,
  `enterInspectElementMode`, `showPanel`): Chrome's ToggleDevToolsWindow closes docked DevTools on
  Console (only Inspect forces them open). Cra runs the same (DevToolsToggle.Command) and asks the
  frontend for the panel or the picker once it reports `loadCompleted`, as DevToolsWindow::DoAction does.
- [O] Sidebar: a Today tab on a developer-mode host (example.com) shows the host under its title; one on
  another host (httpbin.org) shows nothing.

## Live sidebar blur (1 Nov 2026, issue #37)

Arc's sidebar blur is `NSVisualEffectView` only (no `CABackdropLayer` in Arc's or ArcCore's strings). AppKit's
behind-window backdrop layer, dumped from a test `NSVisualEffectView`: `windowServerAware` true, `groupName`
`NSCGSWindowBehindWindowCaptureBackdropGroup`, `scale` 0.125, `allowsGroupBlending` false, filters sdrNormalize,
gaussianBlur (radius 30), colorSaturate (2.4). A bare `CABackdropLayer` defaults to `windowServerAware` false, no
group, `allowsGroupBlending` true. Without the window-server flags the blur is drawn only while the window
redraws: a screen recording over scrolling text showed the text sharp in every frame of a still window (and
blurred again for a moment after each hover), while `screencapture` stills always looked right. `ShellView` now
sets the two flags; recordings stay blurred in every frame. Over solid backdrops (Display P3 captures, same
pipeline) light vibrant themes are unchanged, solid themes are unchanged over black and 7 levels darker over
white, closer to Arc's formula: at #4F7CAC, intensity 0.5, Arc predicts 147/163/184 over white, 0.1.23 measured
153/168/188, now 146/161/181. Cra's solid sidebar still darkens ~12 levels from top to bottom in both builds
where Arc's is flat [U].

## The sidebar follows the active row (Arc 1.171, 1 Nov 2026, issue #47, offline Arc + AX row frames + 120 fps)

- [S] Swift field names: the space list's view store has `isCommandBarNewTabPlaceholderActive` (next to
  `isPulsingNewTabButton`); window state has `sidebarScrollToItemRequest` (`SidebarScrollToItemRequest`),
  `isDismissingCommandBarViaNewTabSelection`, `mousedownSelectionRevertItem`. Tabs menu: "Reveal Tab in Sidebar"
  (no shortcut). Arc's only setting here is `newTabsAtStart`; it has no "New Tab button above tabs".
- [O] Offline Arc (fake home as in "One space") with Victor's sidebar plus 40 Today tabs; row frames sampled
  over AX every 4 ms (`sidebarAllTabList` rows, 41 pt pitch, list viewport 899 pt), keys posted to Arc's pid.
- [O] The New Tab row is the first row of Today, right under the divider.
- [O] ⌘T: while the bar is open the New Tab row is drawn as the open row (selected fill, shadow, primary ink) and
  the selected tab loses its fill; Escape gives it back. The list scrolls to the New Tab row only when it isn't
  wholly in view: from the bottom of the list it ended exactly at the top edge of the viewport; with the row in
  view at the bottom nothing moved (Arc's round ↓ jump button then sat over it, pointing at the selected tab).
- [O] Whatever becomes the open row is brought into view the same way: the tab a commit opens, the tab Escape
  goes back to, Next Tab (⌘⌥↓). As little as shows the whole row: a row above the viewport lands on its top edge,
  one below on its bottom edge (41 pt scroll for a row just below). A row already in view never moves the list,
  also when it sits under 41 pt from an edge. One commit scrolled 64 pt where 23 would have done [U].
- [O] A tab inside a closed folder is not revealed (the folder row doesn't stand in): Escape left the list alone.
- [O] Motion (120 fps recording of ⌘T from the bottom, ~1000 pt): most of the way in the first frame, then
  steadily smaller steps, still after ~0.22 s; the New Tab row arrives already filled.
- Cra: `SpaceListView.revealActiveRow` runs after every rebuild and scrolls when the active row's key changed
  (`activeRowKey`: the active New Tab row, else the selected tab's or split's row), with SidebarListMetrics'
  0.22 s snappy curve; `SidebarUIState.newTabPlaceholderActive` is set by `MainWindowController.openCommandBar`
  for a new-tab bar (not ⌘L, not an empty split pane) and cleared when the bar closes, before a commit selects
  its tab. Settings ▸ Tabs "Show the New Tab button above tabs" defaults on; settings saved by 0.1.15–0.1.23
  (always off) move to on once (`newTabButtonDefaultMigrated`).

## The page area before a page paints (Arc 1.171, 1 Nov 2026, issue #46, 90–120 fps app-only recordings)

Test page: `html{background:#203040}` behind a 1.5 s busy-wait in `<head>`, so nothing paints for 1.5 s.
macOS in Dark, Victor's JYSK space, View ▸ Appearance ("Websites, Easels, and Notes will use") on Automatic.

| Case | Page area until the first paint | Toolbar until the page reports a colour |
|---|---|---|
| Switching between loaded tabs | none: the next page's frame comes straight after | the page's colour |
| New tab or Little Arc, a page Arc has never shown | #000000 | #FFFFFF |
| A tab restored unloaded after relaunch (Cra's slept tab) | #000000 | the page's last colour, remembered across the relaunch |
| Same, Appearance set to Light | #FFFFFF | (not measured) |

So the fill follows the appearance websites get (black or white, not Chromium's #121212 canvas), and Arc
remembers a tab's toolbar colour but not its page colour. Cra 0.1.23 showed #FFFFFF in the page area and the
toolbar for both loading cases (169 frames at 120 fps on the test page). Cra now fills the CEF view and the
pane card with the canvas (CraBrowser.pageCanvasColor), saves the toolbar colour on the tab (TabData.themeColor)
and seeds it into a woken or restored tab's runtime.

CEF still draws the first page of a new renderer transparent (chromiumembedded/cef#3891): with a black
canvas, an unstyled page (no background, no color-scheme) showed black text on black until its load ended
(4 s with a slow image). The page now reports its background on every frame while it is parsed
(kLoadingBackgroundProbe; frames wait for render-blocking stylesheets), so it turns white with its first paint.

### The toolbar on a tab switch (Arc 1.171, 2 Nov 2026, issue #84, app-only recordings at 100 fps)

New tabs (⌘T + a file:// URL) in a fresh main window, macOS Dark, test pages with a 1 s busy-wait in `<head>`;
Cra's runs switch tabs with `cra://debug?selectTab=` in a CRA_TEST_BACKGROUND copy.

- [O] A page Arc has never shown: bar #FDFDFD over a #000000 page until the page paints, and still white about
  16 frames after it. Then it cross-fades white → the page's colour in 14–16 frames, ease in and out. A page
  whose load is held open (an image that never answers) keeps the white bar after it has painted, theme-color
  or not.
- [O] The colour it settles on was the page's background: `html{background:#203040}` with
  `<meta name="theme-color" content="#602040">` gave a #203040 bar (#1C2E3E captured). Cra's probe still prefers
  theme-color (one test page; not changed in #84).
- [O] Little Arc's bar is the space's colour whatever the page (#1A0C20 in Victor's space on all four pages).
- Cra 0.1.25 retargeted the pane card before `browsers.show` created the tab's page, so a restored, slept or
  handed-over tab showed a white bar for 3–5 frames before its remembered colour (Arc: the remembered colour
  at once), on tab and space switches alike. Now the bar takes ToolbarColor (CraCore): the page's report,
  else TabData.themeColor, else white, and fades to a new report over 0.18 s (14–15 frames).

## Sidebar toggle and the command bar's leading glyph (Arc 1.171, 1 Nov 2026, issue #50, live captures at 2x)

Victor's Arc (toolbar shown, full URLs on), window captures by id; Little Arc with keys posted to its pid for
the command bar (posted keys do not reach the main window's ⌘L while Arc is in the background, and Arc's menus
are disabled then).

- [O] Sidebar toggle: the sidebar's title row always has it; the toolbar has one only while the sidebar is
  hidden, floating included (then both show). Windowed: lights 20/43/66, toggle glyph 84–102 (centre 93.25,
  y 23.75). Fullscreen (no lights): glyph 20–38.5 (centre 29.25). Floating panel: lights 25/48/71, toggle 98.25,
  y 28.75 (the panel sits 5 pt in). Cra keeps the toggle 27 pt after its last light (its lights are 20/44/68)
  and draws it at 20–38 in fullscreen; Cra's floating panel sits 8 pt in, so its header is 3 pt right of Arc's.
- [O] Toolbar left group, sidebar shown: ← → ↻ centred 21/58/95 pt from the card edge (the sidebar is 347 pt wide in
  this capture). Sidebar hidden: toggle ← → ↻ at 31.25/68/105/142.25 from the window edge, card 10 pt in, so
  the first glyph is 21 pt from the card edge either way (the old "30 pt" figure was from the window edge).
  Developer mode follows the same rule (Arc 1.168 above: toggle at 93 + ← → ↻⌄ in the title row, URL text 40 pt
  from the card edge, i.e. no toggle in the bar).
- [O] At rest the default toolbar keeps its link glyph before the URL, not the page's favicon.
- [O] Command bar leading glyph = the highlighted row's icon: favicon when it has one (jira → Atlassian from
  history, x.com → X via completion, youtube.com typed → YouTube), globe for a URL row without one
  (example.org), magnifier for a search row ("hello world", "x", "youtulocalhost:3000"). ⌘L untouched or
  emptied: the page's favicon (GitHub), a globe on a page without one (example.com). ⌘T empty: magnifier,
  though its top row is a tab with a favicon. Cra: CommandBarGlyph; `info.circle` is gone.

## Swiping into the Library and the Spaces page overflow (Arc 1.171, 1 Nov 2026)

Offline fake-home Arc (8 hand-built spaces, network denied), 1280×1084 then 1100×1084 pt window on the 2x display.
Swipes were synthesized as HID pixel scroll events (phases began/changed/ended, ~8–10 ms apart) over the sidebar;
a probe app confirmed such an event arrives as `scrollingDeltaX` = the posted value, precise, so "px" below means
scrollingDeltaX points. Recorded app-only at 120 fps; positions from 1-px row crops (card edge, sidebar/page edge),
curves fitted per frame. "p" = Library reveal progress, 0 = space, 1 = Library open.

**Swipe into the Library**
- [O static] `ARCUI.PageSwipeController` {pages: [Page {identifier, width}], trackingState {isTracking,
  isAnimating}, pageOrigins, presentationAdoptionRange, settlingAnimationSession, SettlingAnimation {fromPosition,
  targetPosition, positions, keyTimes, duration} (a sampled keyframe settle), PagingPosition {floorPageID,
  ceilPageID, progress}, nonGesturalScrollState {cumulativeDistance, lastEventTime, lastTriggerTime},
  performsPageDetentHaptics}. The Library is a page before the first space, with its own width.
- [O static, Arc 1.172.1, 8 Nov 2026, issue #260] Page detent haptics: the only
  `performFeedbackPattern:performanceTime:` in `PageSwipeController` is `.alignment` (1), `.now` (1), at
  0x100a278e4. Its method (vtable 0x2e0) runs when `performsPageDetentHaptics` is true, takes the detent page as
  `pages[clamp(frinta(offset / pageWidth))]` (round half away from zero) and ticks when that differs from
  `lastDetentPageID`, storing it. It has one caller, the scroll tracking loop (`nextEventMatchingMask:`, `phase`,
  `momentumPhase`, `scrollingDeltaX`): no tick in the settle, none for a wheel (`nonGesturalScrollState`), so an
  Arc flick that changes the page from under half a page doesn't tick either. The init stores false; no call of
  the setter (vtable 0x208) with a constant true was found, so whether Arc's sidebar turns it on is
  unverified (feel it). Method addresses come from the class descriptor's vtable (generic class: skip the
  16-byte generic header, the 1 param (padded to 4) and the 1 requirement before the vtable).
- [O] On the first space, fingers moving right (positive scrollingDeltaX) pull the Library in; on any other space
  the same gesture goes to the previous space. Fingers moving left inside the Library take it back out. Only over
  the sidebar (the page area was not tried).
- [O] Tracking is linear: the Library content slides in from the left as one piece (rail + list, full opacity),
  its offset = p × Library width, p ≈ px / 834 (so 0.50 pt per px for the 417 pt Library, ~1.2–1.3 pt per px for a
  1044 pt Spaces page; measured 1/834, 1/870, 1/808). A space-to-space swipe measured 0.49 pt per px (one take).
- [O] The sidebar widens during the drag, not at commit: width = 347 + (Lib − 347) × p (347→417 at p 1; 1044 pt
  for a Spaces page), the web page column shrinking with it. Library open → swipe out mirrors it exactly.
- [O AX, Arc 1.172.2, kKr1Xx on #340] The page card keeps its width with the Library open: 1728 pt window, 264 pt
  tab sidebar, card x 264 w 1454; Library ▸ Spaces (5 spaces, 1536 pt) x 1536 w 1454; Archived Tabs (417 pt)
  x 417 w 1454. It moves with the Library's right edge and past the window's, which cuts it off, so the page is
  never laid out again for a narrow column. Cra follows it (`LibraryWidth.page`); the "column shrinking" above
  and the 56 pt column below are the slice of the page that shows. [U] the in-between frames of a swipe, the
  Library opened with the sidebar hidden (Cra keeps the whole card's width) and a tab sidebar wider than 417
  (Cra lets the page fill what the Library leaves).
- [O] The space's own content fades, alpha ≈ max(0, 1 − 2p) (row contrast 1.00/0.60/0.29/0.08/0 at p 0/0.2/0.36/
  0.46/0.5), and shrinks a little: scale ≈ 1 − 0.1 p about a point near (417 pt, window mid-height) [I, fitted from
  the selected row, favourites card and traffic-light positions]. The traffic lights travel with that content and
  are gone mid-swipe; they reappear on the Library. No window tint/background change: the Library sits on the
  space's own theme.
- [O] Commit, slow release (no velocity): p > 0.5. 412 px (p 0.494) snaps back, 424 px (0.508) opens; the same 0.5
  on the way out (400 px stays, 440 px leaves); toward a 1044 pt Spaces page 400 px stays, 460 px opens.
- [O] Commit with velocity, 417 pt Library: any release still moving opens it: 80 px at ~200 px/s, 30 px at
  ~1250 px/s, 240 px with a 60 ms stop before lifting; a 150 ms stop (240 px) snaps back. Toward a 1044 pt Spaces
  page flicks of 80, 180 and 300 px at ~3750 px/s all snapped back [U why: velocity projection apparently in points].
- [O] Settle (open, cancel, and close alike): critically damped spring, ω ≈ 30.6 rad/s (ζ 0.96–1.0, no overshoot),
  i.e. stiffness ≈ 935, damping ≈ 61, mass 1 (SwiftUI `.spring(response: 0.205, dampingFraction: 1)`), within
  0.2–0.25 px rms; ~0.2 s to within 1 %, ~0.27 s to rest. It starts from the release velocity: a 300 px/s-ish
  release starts gently, a flick (fit v0 = 25 × displacement/s) leaves at once. Cancel = same spring back to p 0.
- [O] Rubber band past the Library (fingers right while it is open): the whole Library moves right at ~0.07 pt per
  px (300 px → 20.5 pt; ~0.14 of the unbanded 0.5, nearly linear over that range, fits D(1 − 1/(0.15x/D + 1)),
  D 215, x = 0.5 px), the sidebar keeps widening by the same formula (p > 1), and springs back in ~0.2 s.
- [U] Real-trackpad feel (momentum events were sent with one flick only; Arc does not need them to commit).
- Frames: scratchpad `arc/rec/t2-strip.png` (paused mid-drag, at release, settling, open), `arc/rec/t4-sheet.png`
  (swipe out), `arc/rec/t1.mov`–`t4.mov`.

**Spaces page with 8 spaces**
- [O static] `SpaceManagementViewControllerSpacesPage` holds an `NSScrollView` + `NSCollectionView`; the strip is a
  `SpaceManagementHScrollCollectionViewItem` with its own private `ScrollView` subclass.
- [O AX] Sidebar = window width − 56 pt whenever the cards don't fit (500 → 444, 900 → 844, 1100 → 1044, 1728 → 1672,
  live while resizing, no maximum seen); the web page keeps a 56 pt column (8 spaces need 112 + 2208 pt, more than
  this 1728 pt display, so the "fits" case was not reached). Rail 112 pt, strip scroll area = the rest (932 pt at
  1100); content 2208 = 24 + 8 × (240 + 24) + 48 pt add-space button + 24. Cards are clipped at the sidebar edge.
- [O] Horizontal two-finger swipes scroll the strip 1:1 over a card's tab list, a card's empty body, the gaps
  between cards alike; elastic at both ends (~17 pt stretch for 340 px), ~0.25 s spring back. A swipe that starts
  inside the strip never leaves the Library; a new swipe that starts with the strip already at its end (pushing
  past it) becomes the Library page swipe out (content and sidebar edge follow, then the usual settle). Over the
  rail the same swipe did nothing (strip at its end).
- [O] Vertical mouse wheel and vertical trackpad scroll do not move the strip. Shift + wheel scrolls it, 10 pt per
  line; at the strip's end further Shift + wheel left the Library to the first space (non-gestural page change).
- [O AX] Scroller: AppKit overlay AXScrollBar, horizontal, 17 pt track at the bottom (y 1060–1077 in a 1084 pt
  window), inset 19 pt from the scroll area on each side, knob 4 pt tall (373.5 of 894 pt for 932 of 2208), shown
  while scrolling.
- [O] Theme editor (a card's brush, AXPress): a separate 382 × 534 pt window, left edge flush with that card's
  right edge, top at the window top, over the neighbouring cards and the page, overhanging the browser window's right
  edge when the card is near it (Games card at the strip end: 1339–1721 in a window ending at 1491).
- [U] Whether the page column has a minimum when the window is narrower than 500 pt; the width rule once all
  cards fit on a wider display.
- Frames: `arc/rec/b1.png` (1100 pt window), `arc/rec/b3-main.png` (theme editor), `arc/rec/t10.mov`, `t12.mov`.
- [Cra, 1 Nov 2026] Victor found Arc's half-speed, sidebar-widening drag "way too slow / laggy" and asked for the
  space swipe's animation instead. Cra's `LibrarySwipe` (CraCore) treats the Library as the page before the first
  space, its right edge 1:1 under the fingers, with the space swipe's rubber band, release rule (> 0.8 pages/s or
  past half) and settle (critically damped, ω = 2π/0.4). Like Arc the sidebar widens with the reveal (base +
  (Library − base) × r), so it lands at the Library's width with nothing left to resize (a resize after landing
  looked ugly with a narrow sidebar). Embedded pages keep their size under their cards during the swipe
  (`ShellView.freezePages`) and resize once when it lands: a page resize per event made Chromium lay the page out
  each time and stalled the swipe for a second. The Library's search takes focus only after landing (focusing it
  mid-swipe flashed a system panel). The Spaces page follows Arc: sidebar = window − 56 pt, live on resize; cards scroll
  sideways under two fingers (over card lists too) and Shift+wheel; a swipe that starts with the cards at their
  end leaves the Library; the brush's theme editor sits flush with the card's right edge.

## Hidden sidebar with two windows (Arc 1.171, 2 Nov 2026, issue #82, live Arc, HID pointer, window-id captures)

Two new Arc windows, both with View ▸ Hide Sidebar and a tab selected, captured per window with
`screencapture -l` (each window's own pixels, even where another window covers it).
- [O] Stacked at the same frame, the pointer at the shared left edge: only the front (key) window's sidebar
  comes out; the back window stays hidden and stays behind.
- [O] The front window moved 400 pt right, so the back window's edge is uncovered and on top under the pointer:
  the back (non-key) window does not reveal. The same motion at the key window's edge reveals it. So Arc
  reveals only in the key window, not in whichever window is under the pointer.
- [O] A pointer jump into the strip did not reveal; moving inside it did (a few points up or down). Cra
  reveals on arrival.
- [U] An inactive Arc (another app frontmost); hidden-sidebar windows of other apps over Arc's edge.
- Cra: `FloatingSidebarController.isKey` gates both reveal paths (the 30 Hz poll and the shell's tracking
  area): this window, or one of its child windows (page, DevTools, the floating panel), must be key.

## Moving a tab to another space (Arc 1.171, 2 Nov 2026, issue #86)
- [O AX] No key binding: Arc's menu bar has no move-to-space item (Spaces: New Space…, Edit Theme…, Rename Space,
  Change Profile, Next/Previous Space ⌥⌘→/←, one item per space ⌃1…, Manage Spaces…; Tabs has none either), and
  the binary's `moveToSpace` / `moveToSpaceTabContextMenuOption` are analytics names, not key-binding actions.
- [O] Command bar: typing "move" on a Today tab lists "Move to Today in <space chip>" for each other space, with no
  shortcut glyph (strings also have "Move to Pinned in <space>"). Choosing it closes the bar, takes the row out of
  the old list, then plays the ordinary space switch (list slides, theme cross-fades, ~300 ms): the window follows
  the tab, which sits at the top of the new space's Today, selected, page unchanged. Recording `arc-move.mov`
  (scratch, 40 fps), not kept.
- Reported by Anoninz on #86, not captured here: the sidebar's right-click Move to ▸ <space> on the open tab
  follows too (the row leaves, Arc switches to that space and selects the tab).
- [O] What the space the tab left selects afterwards: nothing (measured for #105, see "The tab shown after ⌘W").
- [U] What Move to ▸ does on a tab that isn't open: other sessions were driving Arc at the time and a posted ⌃2
  never reached the window.
- Cra: `SidebarStore.moveTabAndFollow` for the command bar's Move Tab to <space> and the new Move Tab to Space N
  (⌃⌘1–9, Cra's own: ⌘ added to Go to Space N; neither Arc nor macOS binds ⌃⌘ + a digit). A pane brings its split.
  The sidebar menu's Move to Space follows when it moves the open tab or its split; another tab moves on its own. The window that follows leaves nothing selected in
  the old space; another window that had it open there opens the next tab, picked as on close.

## Sending a Little Arc's page to a space (Arc 1.171, 2 Nov 2026, issue #92)

Victor's Arc, a second window of my own (File ▸ New Window over AX, switched to JYSK through the Spaces menu while
Arc was frontmost, closed afterwards), Little Arcs opened with `open -a Arc https://example.com/?cra92…`, the spaces
popover driven by AX (the chevron is `openInSpaceExpander`, the rows are AXButtons named after the space).

- [O AX] Window A on Victor (used last), window B on JYSK. Picking JYSK in the Little Arc's popover closed the Little
  Arc and opened the page in **window B**, which came forward and became main; window A kept Victor.
- [O AX] No shortcut for it: Tabs ▸ "Open Little Arc or Peek in…" is ⌘O (the target space), Spaces lists the spaces
  under ⌃1…; a ⌃2 posted to Arc's pid while the Little Arc was key changed nothing.
- Offline copy (cra-88's fake home, no network, spaces Alpha/Beta/Gamma, up to three windows W1–W3, Little Arcs
  from File ▸ New Little Arc Window; the popover rows are AXButtons `d='<space>'` in their own window, present only
  while it is open; the real chevron is the second `openInSpaceExpander`, `d=''`):
  - [O AX] "Open in <space> ⌘O" names the focused space of the window used last, read when the Little Arc takes focus:
    W1 switched Alpha → Beta while the Little Arc sat behind it, the button still said Alpha until the Little Arc was
    focused again, then Beta. Using W2 (Gamma) after opening the Little Arc from W1 (Alpha) made it say Gamma.
  - [O AX] ⌘O and a click on that button open the page there: in W1's new space, and in W2 after W2 was used.
  - [O AX] No window shows the picked space: the window used last switches to it and takes the page.
  - [O AX] Two windows show it: the one used last if it is one of them, else the frontmost of them (W1 and W2 on Beta,
    W3 on Alpha used last: whichever of W1/W2 was raised later took the page, both ways round).
  - [O AX] Only a minimized window shows it: Arc unminimizes that window and opens the page there.
- Cra: `SpaceWindow` (CraCore) picks the window: the one in use if it shows the space, else the frontmost one that
  does, else the one in use, which switches. It applies to ⌘O, the popover, the command bar's Move to <space> and
  Move Tab to Space N (⌃⌘1–9, #86), which in a Little Window sends its page (#92, Cra's own like ⌃⌘N itself). The
  Little Window's target follows the window used last when it takes focus (`refreshTarget`), as Arc's does.
  Until a space is picked in it (#316, Cra's own): "Switch to <space>" in a Little Window's command bar changes its
  "Open in" and not the browser window's space, and the browser window no longer moves it. Only that window's: the
  next Little Window follows the window used last again, so a link from another app doesn't open in a space (and its
  sign-ins) picked earlier; Air Traffic Control's Default (Little Window + space) sets that for good (CraCore
  `LittleWindowTarget`; scenario little-window-space-pick).

### The ⌘O menu row (Arc 1.172.2, Victor's Arc, 11 Nov 2026)

Little Arcs opened with `open -a Arc https://example.com/?cra-open-in…`, the menu bar read over AX with and without
one in front, the Tabs menu opened over AX and captured, ⌘O posted to Arc's pid.
- [O static] MainMenu.nib has one row for it, `openTabIn`, titled "Open Little Arc or Peek in" (the name Settings ▸
  Shortcuts lists as "Open Little Arc or Peek in…", ⌘O), with no command bar keywords. The nib has no row for
  ⇧⌘O (`showLittleArcOpenInMenu` is a key binding only) or for closing every Little Arc.
- [O AX] With a Little Arc in front the row is in **Tabs**, after Pin Tab and before New Folder…, titled
  "Open in Victor" (the space the Little Arc's own "Open in , Victor, ⌘O" button names), with that space's emoji
  as its image, ⌘O, no ellipsis. With the browser window in front the row isn't in the menu at all, enabled or not.
  The Window menu has none of the Little Arc rows either way (only the "Little Arc — <title>" window entry).
- [O AX] ⌘O moved the page at once: the Little Arc closed and the browser window on Victor showed
  example.com as its selected tab. No space picker; that is the ⌄ / ⇧⌘O.
- [O AX] The browser window's command bar has no row for it: "Open in" and "Peek in" gave only the search row,
  history and search suggestions.
- Peek: the nib's name says the row serves a Peek too. Not opened live (a Peek needs a click in a pinned tab).
- Cra: `TabsMenu` (CraCore) has the row's place, title and when it shows. Window ▸ Open Little Window in Space is
  gone, and the action is "Open Little Window or Peek in…" under Tabs in Settings ▸ Shortcuts. ⌘O from a Peek
  expands it into the parent window's space (scenario little-window-open-in-row).

## ⌘Return in the command bar and closed folders that keep their tab (Arc 1.171, 2 Nov 2026, issue #85)

Victor's Arc, a window of my own (File ▸ New Window over AX, closed afterwards), keys posted to Arc's pid while it
was frontmost, 1x region captures and 100 fps recordings; test tabs archived afterwards.

- [O] ⌘Return in the URL editor (⌘L, a page open) or the new-tab bar (⌘T): the highlighted row opens in a new tab at
  the top of Today, the current tab stays in front and the bar stays open with what was typed; each ⌘Return opens
  one more (two ⌘Returns, two tabs). A "Switch to Tab" row opens its address again as a new tab rather than switching;
  a search row opens the search. The tabs are saved read (`isUnread` false). Cra: the field editor reports ⌘Return as
  `noop:`, never `insertNewline:` (KeyChord.isCommandReturn), CommandBarController.commitInBackground,
  MainWindowController.openInBackground.
- [O] Arc only says so when the sidebar is hidden: "New Tab Created" (`backgroundTabCreated`, Toasts.ShinyToastView;
  "New Tab Created in %@" exists for another space). With the sidebar out, only the new row appears in Today. The toast:
  138 × 42 pt at 1x, 8 pt below the top of the page area (below the toolbar; with the inline URL editor open, below
  its input row) and 9 pt in from its right edge; 14 pt medium black text, 12 pt either side; ~10 pt corners; a
  1 pt outline at ~69 % of the fill; fill 220/226/184 at the top to 208/218/163 at the bottom over a dark page on a
  yellow/green theme (`ShinyToastBackgroundBasedPalette`). It springs in from its top centre (width 0.41 → 1.04 at
  ~0.2 s → 1.0 by ~0.4 s, i.e. ≈0.3 s response, damping 0.67), stays ~4.85 s and shrinks into its top while fading in
  ~80 ms. Another ⌘Return while it is up restarts its time (gone 4.77 s after the last one) and bumps it,
  width 1 → 1.044 (~40 ms) → 1 by ~0.2 s, rather than springing in again. On the default theme in dark mode
  (JYSK space) it is dark with white text: 43/24/102 → 33/19/79, outline 26/15/62, i.e. the same hue at
  saturation 0.76, brightness 0.40 → 0.31 (outline 0.24); the light one is saturation 0.19 → 0.25, brightness
  0.89 → 0.85 (outline 0.61) in the theme's hue. Cra: ShinyToast.
- [O static] It is Arc's one toast (Toasts.ShinyToastView, `ToastContent`): the same component carries
  "Copied Current URL" (`copyTabURL`), "Cannot Add New Pane" (`maxNumberPanes`), "Screenshot Copied to Clipboard",
  "Pinned Tab to …", zoom changes, undo and more; some kinds add an SF Symbol (`quote.bubble.fill`,
  `checkmark.shield.fill`, `xmark.octagon.fill` sit next to their strings). Cra shows its confirmations with
  ShinyToast (MainWindowController.showToast), not Dia's nav-bar status. [U] Whether the copy and pane-limit
  toasts carry a symbol, and where they sit with the sidebar out: the live check was cut short (Victor in a call).
- [O] Return on a "Switch to Tab" row for a pinned tab two closed folders down (Netfinder ▸ Endpoints ▸ tab): no folder
  opens. The tab is listed one level under the outermost closed folder (its row slides in, ~0.15 s), Endpoints stays
  hidden, and the folder's glyph gets three dots (2 pt, 4 pt pitch). StorableWindows.json keeps it per window as
  `expandedItems: [folder, {"peeked": {"_0": [tab ids]}}]`; the tab stays listed after another tab is picked. The bar
  lists only the window's space's tabs; a typed URL puts the typed row first and the "Switch to Tab" row second.
  Arc also has Tabs ▸ Reveal Tab in Sidebar (`revealTabInSidebar`). Cra: FolderPeek (CraCore),
  WindowPrefs.peekedFolders, SidebarStore.peekedTabs/setExpanded, FolderGlyphView's dots.
- [O] Real clicks (cliclick, Victor idle) on a peeked folder never open it: with the peeked tab open it stays
  closed with the tab listed (two clicks), with another tab open it closes for good and drops the peek and the
  dots. A folder without a peek opens as usual. Arc's window state then has no entry for it. So a click on a
  closed folder that keeps tabs in sight means "close", keeping only the open tab (as the 29 Oct folder-peek
  notes found). Cra copied this until GitHub #213 (6 Nov 2026): a click on a closed folder now always opens it,
  peek or not (FolderPeek.clickOpens), since Arc's way left the rest of the folder out of reach while one of its
  tabs was open. Closing it still keeps the open tab in sight.

## Secure DNS (Arc 1.171, 2 Nov 2026, issue #110, live net log)
- [O] Arc leaves Chromium's default. Victor's Arc `Local State` has no `dns_over_https` key, and a net log of Arc
  started with `--log-net-log` (in the background, no clicks) shows `secure_dns_mode: 1` (automatic) with
  `doh_config.servers: []` in every DNS config event: the system resolver, encrypted only when it is a known DoH
  server. No Arc policy is installed. The binary's `dns.google` templates are Chromium's own provider list.
- [O] An Arc with `"mode": "secure"` and `https://dns.google/dns-query{?dns}` (the #110 report) is what Chromium
  writes when Google is picked in arc://settings/security, not something Arc seeds.
- Cra: no change to the default, so a work network's own DNS keeps resolving its internal names. CEF builds the
  same provider list as Chrome (OS default, custom, DNS4EU, Cloudflare, CleanBrowsing, OpenDNS, Google) in
  chrome://settings/security; a choice persists in Cra's `Chromium/Local State` across restarts. `cra.log` says
  what is in effect at launch and after each change (`secure dns: automatic, no provider (system resolver)`, `secure
  via dns.google`, `off`), and Export Diagnostics' summary has a `Secure DNS:` line (`SecureDNS` in CraCore, hosts
  only).
- Cra (3 Nov 2026, issue #133, a deviation: Arc and Dia have no such row): Settings ▸ Privacy ▸ Connections has a Secure
  DNS menu under "Always use secure connections": Automatic (the default), Off, Google, Cloudflare, Quad9, OpenDNS,
  CleanBrowsing (Family Filter), DNS4EU (Protective), Custom…. It reads and writes the same two Local State prefs as
  chrome://settings/security (`SecureDNSPrefs`, `SecureDNSProvider` in CraCore; `setSecureDNSMode:templates:` in
  CraCEF), so settings.json keeps no copy, a fresh install still has no `dns_over_https` key, and a choice made on
  either page shows on the other at once. The write is live: a net log shows `secure_dns_mode` 1 → 2 and DoH queries
  to dns.google with no relaunch. Custom takes whitespace-separated `https://` templates with a host, path kept as
  typed (NextDNS ids). The footnote is `SecureDNS.summary`, built from the same value as the log line. A
  DnsOverHttps* policy makes the menu read-only.

## Shift + wheel switches spaces (Arc 1.171, 2 Nov 2026, issue #93, live Arc, HID wheel events)

Victor's Arc (2 spaces, Victor and JYSK), the pointer over the sidebar's list, line-unit wheel events posted at the HID
tap with a real Shift key held around them; the space read from each window's `sidebarSpaceName` AX frames.
- [O probe] macOS turns Shift + vertical wheel into a horizontal wheel before the app sees it: `scrollingDeltaX` =
  the posted lines (1.0 per line, point delta 8), `scrollingDeltaY` 0, not precise, no phases, Shift in the flags.
  A sideways wheel without Shift arrives the same way (point delta 10 per line) without the flag.
- [O static] `PageSwipeController.nonGesturalScrollState {cumulativeDistance, lastEventTime, lastTriggerTime}`.
- [O] Over the sidebar both Shift + wheel and a sideways wheel page between spaces. Negative `scrollingDeltaX` = the
  next space, positive = the previous one (as two fingers moving right go back). No wrap at the last space; before
  the first space the Library comes in (its Spaces page here), and the opposite flick takes it out again, over the
  rail as over the cards (cards that fit have nothing to scroll). Over the page: nothing. Vertical wheel: nothing.
- [O] Distance: one 1-line event never switches; one 2-, 3- or 6-line event always does. Two 1-line events switch
  35 ms apart (4/4), 45 ms apart half the time (1/2 + borderline runs at 50 ms), 65, 80, 150 ms apart never
  (0/6); eight notches 100 ms apart never. So quick events add up and a gap of ~45 ms forgets them.
- [O] Cooldown: 3-line events every ~22 ms switched once for bursts up to 0.245 s long, twice for 0.254–0.306 s:
  one switch per 0.25 s. Ten 1-line events 30 ms apart (first switch at the 2nd event) switched once, so what
  arrives during the cooldown is dropped.
- [O 120 fps] The switch animates like a space change: the header slides in and the tint follows, ~0.15–0.2 s.
- [O static, 4 Nov 2026, issue #93 follow-up] The handler (arm64 0x100a2193c in Arc 1.171's main binary, called
  with the event; `CACurrentMediaTime` for the clock): within 0.25 s of the last switch it returns before noting
  the time; a gap over 0.05 s (the constant is 0.05) zeroes the sum; then time = now, sum += `scrollingDeltaX`,
  and past |1| it pages, zeroes the sum and notes the switch. One sum: a turn subtracts, it doesn't restart.
  Direction (0x100a21b00): sum < 0 → next unless `isDirectionInvertedFromDevice`, sum > 0 → previous unless
  inverted, so the sign is XORed with natural scrolling. The probe above posted synthetic wheels (not inverted),
  which is why "negative = next" held; a real mouse with natural scrolling on (macOS's default) sends inverted,
  flipped deltas, and Cra 0.1.27 ignored the flag and paged backwards (reported on #93 by Anoninz). CGEvent field
  137 = 1 makes a synthetic wheel report `isDirectionInvertedFromDevice`.
- Cra: `WheelSpaceSwitch` (CraCore) with distance > 1 line, pause 0.05 s, cooldown 0.25 s, direction XOR inverted; the window controller's
  scroll monitor feeds it non-precise horizontal wheels over the sidebar (docked or floating, not incognito). A
  step focuses the space on Cra's usual space-change spring (Dia's 0.4 s, slower than Arc's here), or slides the
  Library in or out like its button. On the Spaces page the cards take the wheel first (10 pt per line, as in Arc)
  and the wheel leaves the Library only at their end.

## Mouse back and forward buttons (Arc 1.172.1, 7 Nov 2026, issue #233, static: main binary arm64)

Reported on #233: in Arc a mouse's back and forward buttons over the sidebar switch spaces.
- [O static] `Arc.SidebarView` implements `otherMouseUp:` (method list 0x1036918e0, with `hitTest:`, `mouseDown:`,
  `menuForEvent:`; imp 0x100313594 → 0x1003134a0). Behind a Bool stored property being true (not identified),
  `buttonNumber` 3 sends the spaces reducer's empty case 3 and 4 sends case 2. That enum's empty cases, in order
  (`__swift5_fieldmd`): `didTriggerCreateSpaceGesture`, `didTapCreateSpaceButton`, `focusNextSpace`,
  `focusPreviousSpace`, `iconPickerWillClose`. So back (3) = `focusPreviousSpace`, forward (4) = `focusNextSpace`, on
  the button's release; the press does nothing there. No `otherMouseUp:` on the page, where Chromium's own
  back/forward runs.
- [O static] NSEvent helpers next to `PageSwipeController` (0x100a0d608…0x100a0d6b8): `otherMouseDown` with button
  2, `otherMouseUp` with button 3 and with button 4.
- [O live] (contributor, 12 Nov 2026) Back on the first space brings the Library in and forward takes it out,
  as a swipe does, and the ends don't wrap. [U] What the Bool gate is.
- Cra: `MouseButtonSpaceSwitch` (CraCore) maps 3 → −1 and 4 → +1. The window's `otherMouseUp` monitor, over the
  sidebar (docked or floating, not a Little Window), turns the sidebar's page like the wheel (`stepSidebarPage`: the
  Library before the first space, no wrap) and swallows the event; anywhere else the event goes on. Scenarios
  `mouse-buttons-switch-spaces`, `mouse-buttons-library`.
- Cra, follow-up (reporter, MX Master 3S, Logi Options+ running): that mouse does not emit button 3/4. Options+
  eats the HID report; a Back keystroke assignment types ⌥← (key code 123) and Forward types ⌥→. Assigning ⌥←
  in Options+ still did nothing, because Cra only listened for `otherMouseUp`. The same type maps ⌥← / ⌥→ (Option
  alone; ⌥⌘← stays Previous Space). A `keyDown` monitor hit-tests the pointer, not the key's window (the focused
  page): over the sidebar `stepSidebarPage`, otherwise `goBack`/`goForward`, and the key is left alone when a
  text field has it (⌥← moves by word). Console shows `Cra: mouse key back: …` when the key arrives.

### Extension action icons, badges and tooltips (Arc 1.171, 2 Nov 2026, issue #106, offline Arc + probe)
- [O live] Offline Arc (fake home with the Storable*.json files minus both sync states, `--load-extension` with
  a probe, pinned through the fake profile's `extensions.pinned_extensions`). Probe: red top-level `icons`, blue
  `action.default_icon`, then `setIcon` (green disc), `setTitle` and `setBadgeText` on alarms.
- Icon: the pinned button and the Site Control Center tile show the action's `default_icon` (blue), not the
  top-level `icons`, and follow `setIcon` at once. The menu bar's Extensions menu keeps the manifest's action icon
  (blue) after `setIcon`. Drawn 16 pt (32 px) in the top bar.
- Tooltip: none on a pinned extension button after 8 s of hover (Back shows "Go back ⌘[" within 3 s), so
  `setTitle` shows nowhere there. The Site Control Center tile's tooltip is the extension's name.
- Badge: Chromium's IconWithBadgeImageSource at half size, its 28 pt icon area centred on the 16 pt icon. "7" is
  7 × 7 pt and "42" 8 × 7 pt, right-aligned 1 pt in from the icon's bottom right. "1234" is 14 × 7 pt, centred
  (20+ in Chromium's units). A 0.5 pt ring is cut out of the icon around the badge. Text is white or Google
  Grey 900 by contrast unless `setBadgeTextColor` set one. A transparent `setBadgeTextColor` is refused and keeps
  the old colour. With no colour set, the badge is #282828 in dark mode (Chromium's neutral container; light mode
  not seen). The tile in the Site Control Center carries the same badge; the menu doesn't. Text widths match SF
  bold at optical size 22–26 (CoreText's own 9 pt instance makes "42" a pixel wider).
- Custom icons: Arc has none, so Cra's toolbar icon styles (#9) stay toolbar-only.
- Cra: `extensions-action-updates.patch` reports icon, title, badge text (or the declarativeNetRequest count), badge
  and text colour. `ExtensionBadge` (CraCore) lays the badge out; `ExtensionStore.badged` draws it into the icon.
  Captured side by side with the same probe, Cra matches Arc's five states to the pixel (text ±1 px antialiasing).

## Extensions per profile, options pages and the proxy (Arc 1.171, 2 Nov 2026, issue #107)

- [O static] Pinned extensions are per profile: Arc's `arc::BrowserContext` (one per Chromium profile) has
  `getPinnedExtensionOrder` / `setPinnedExtensionOrder:`, `browserContext:didChangePinnedExtensionOrder:` and
  `arc::BrowserContext::Extensions::Delegate::DidPinnedExtensionOrderChange`, over Chromium's
  `extensions.pinned_extensions` pref. This Mac's Arc has only the Default profile (two pins), so two lists were not
  compared live. Cra: `PinnedExtensions` (pinned-extensions.json), where the old single list serves every profile until
  one pins or unpins something of its own.
- [O] Arc has no per-space extension switch. A space gets the extensions of the profile it is bound to, and an
  extension is turned off for one profile in that profile's arc://extensions. Cra does the same with
  chrome://extensions opened from a space on that profile (Extensions ▸ Manage Extensions…). Verified on a test copy:
  an `Extensions/` extension turned off in a Work profile left that profile's toolbar and proxy, and kept running
  in Default.
- [O live] Options page across spaces: offline Arc (fake home, see "One space") with this Mac's two spaces and an
  unpacked probe (`--load-extension` + `--disable-features=DisableLoadExtensionCommandLineSwitch`) whose service
  worker calls `chrome.runtime.openOptionsPage()` when a tab opens `…#cra-opts`, driven by Arc's AppleScript (`tell
  space "…" to focus`, `make new tab`). The options page opened in space 1. Asked again from space 2, Arc went back
  to space 1 and selected that tab, with no second options tab. Arc has no options-page code of its own
  (`runtime.openOptionsPage` → Chromium's `ShowSingletonTabOverwritingNTP`). Cra keeps that, per profile: another
  profile's copy of the page is never reused (`ExtensionPagePlacement`).
- [O] Two extensions setting the proxy: Chromium applies the latest `last_update_time` among the enabled ones
  (ExtensionPrefValueMap::GetEffectivePrefValueController; on a tie, the later ID). The other gets
  `levelOfControl: "controlled_by_other_extensions"`, which CEF reports correctly (checked with two probes).
  `--load-extension` folders are reinstalled on every launch, but the winner stayed the same over three launches.
  `ForceWebRequestProxyForTest` makes `MayHaveProxies()` always true, so a proxy extension enabled later does not
  reset the URL loader factories. Cra logs the winner and the overridden ones per profile when they change, and
  Export Diagnostics' summary.txt has a "Proxy:" section.

## Importing Arc's profiles (3 Nov 2026, issue #131, reporter's Arc: seven spaces on six profiles)

- [O static] Each space in StorableSidebar.json names its Chromium profile: `profile` is `{"default": true}` or
  `{"custom": {"_0": {"directoryBasename": "Profile 2", "machineID": …}}}`. The folder's name in Arc's space
  menu is `User Data/Local State` → `profile.info_cache[<folder>].name`. Each profile keeps its own cookies, logins,
  `extensions.settings` and `extensions.pinned_extensions`.
- Cra's import makes one Cra profile per Arc profile besides Default (reusing a Cra profile of the same name) and
  puts the spaces on it. Each Arc profile's cookies and passwords are staged for the Cra profile its spaces landed
  on. A Cra profile Chromium has not opened yet gets Cookies and Login Data with Default's schema and meta rows
  before Chromium starts, so the first page is signed in. Arc's pins become that profile's list. An Arc profile no
  imported space uses goes to Default, as everything did before.
- `--load-extension` installs in every profile (`ExtensionService::Init` runs it per profile, and command-line
  installs are never restored from prefs). `extension-profiles.patch` (CEF codecs9) adds
  `--cra-load-extension-profiles`: for each `--load-extension` path, in order, the profile folders that load it
  ("Default|Profile <id>") or `*`. An imported extension loads only in the Cra profiles of the Arc profiles that
  had it turned on (extension-profiles.json); one every profile had, or one from an import that bound no profiles,
  still loads everywhere. CDP's `Extensions.loadUnpacked`/`uninstall` only reach the default profile, and a
  hand-written `extensions.settings` entry fails Secure Preferences' MAC check, so neither could do this.
- Checked on a test copy with a three-profile fake Arc: each space's page read its own profile's cookie, Chromium's
  per-profile prefs held exactly the probes that profile was given, and the toolbar and Extensions menu differed per
  space as in Arc.
- Installs imported before this: Settings ▸ Profiles ▸ Rebuild from Arc… (also the command bar's "Rebuild Profiles
  from Arc…"). It moves spaces still on Default onto their Arc space's profile, matched by name (a name Arc or Cra
  uses twice is skipped), stages those Arc profiles' sign-ins (or, if the Keychain refuses, moves them signed out
  after asking), scopes the extensions the old import left loading everywhere (profiles made in Cra keep them),
  seeds the pins and restarts. Sign-ins made in Cra since the import stay with Default.

## The tab shown after ⌘W (Arc 1.171, 2 Nov 2026, issue #105, offline Arc driven through its menus)
Offline Arc as in "One space": one space with pinned S and P2 and Today C, B, A, D (A, B, C saved with
`activeTabBeforeCreationID` and `referrerID` = S, unread), the selected tab and the window's
`itemLastActiveDates` set in StorableWindows.json, then Tabs ▸ Next/Previous Tab and File ▸ Archive Tab (Close
Tab on a pinned tab) pressed over AX, a window capture after each step. Setting AXSelected on a row
doesn't pick a tab, and the selection saved in StorableWindows.json wasn't always honoured; navigate instead.
- [O] Arc goes back to the tab shown just before the closed one, if its page is still loaded: D → A, close A → D
  (not S, the tab A was opened from, loaded or not); S → P2 → close P2 hands back to S only while S is loaded.
- [O] Only that one tab counts. D → A → B, close B → A, close A → C (the neighbour above), not D: Arc doesn't
  walk further back. A previous tab without a page doesn't count either: one restored from `itemLastActiveDates`
  that hasn't loaded since launch, or a pinned tab closed with ⌘W (Arc never reloads it on a later close).
- [O] Otherwise a Today tab hands over to its neighbour, the one above first (B → C, D → A), the one below at
  the top (C → A), loaded or not. The last Today tab hands over to nothing, with pinned tabs still in the
  sidebar. A pinned tab hands over to nothing (no neighbour), even with Today pages loaded.
- [O] "Neighbour" means the Today rows on screen: with a closed folder above it (tabs X, Y inside), closing D hands
  over to nothing; with the folder open (`AXDisclosing` on its row over AX), to Y, the row above inside it.
- [O] A favorite closes like a pinned tab: back to the previous tab while it is loaded (F1 after D → D), else nothing.
  Tabs ▸ Next Tab runs through the favorites first.
- [O] The tab a close hands over to loses its unread mark, as when it is picked.
- [O] Splits (a `splitView` item needs `layoutOrientation`, `focusItemID` and `itemWidthFactors`, as Arc saves it;
  without them Arc moves the split into a pinned "Recently recovered" folder): a split row as the neighbour opens the
  split on its focused pane. Closing a pane keeps the other one and the tab shown before the split (D → split, close
  L → R, close R → D, not the neighbour C). Closing a pinned split hands over to nothing even with the tab shown
  before still loaded (D → pinned split, Close Tab → nothing; twice).
- [O] Previous tabs are per window: window 1 A → B, window 2 D → C, close C in window 2 → D (not B).
- [O] A space switch counts as showing another tab: space 1 B, space 2 Y → X, Previous Space (B), Next Space (X),
  close X → W (the neighbour above), not Y. Closing never switches spaces.
- [O] Command bar "Move to Today in <space>" on the open tab: the window follows, and the space it left has nothing
  selected when you come back (C → B, move B, Previous Space → nothing; not C, not the neighbour A).
- [?] Not measured: Move to ▸ on a tab open in another window.
- Cra: CloseSuccessor (CraCore) with SidebarStore's per-window `previousTab` (not saved; set in `updateWindow`
  whenever what the window shows changes) and `hasPage` (a window's browser manager has the page). A tab put to sleep has no page, like Arc's unloaded tabs.
  `activeTabBeforeCreationID` is still saved and imported but no longer picks the next tab.

## The loading bar above the card (Arc 1.171, 2 Nov 2026, PR #130, Kevin McKelvin's 60 fps recordings)
Measured frame by frame by Kevin McKelvin from screen recordings of Arc (1.4 px per pt), against a local server
that waits 3 s before answering and then serves a page whose image takes 5 s.
- [O] A 4 pt bar, centred over the card in the margin above it.
- [O] Waiting (the request is out, nothing committed): a 48 pt pill at 75 % white fades in over 0.7 s, out over
  0.65 s and stays off for 0.25 s (a 1.6 s cycle).
- [O] Loading (the main frame committed): the pill widens to a 130 pt track at 18 % white in about 0.35 s. A 76 %
  white segment sweeps it every 1.12 s: its head runs left to right in 0.37 s, then its tail, then the track
  stays empty for the rest of the cycle. Both edges move at a steady speed.
- [O] Done: the whole track lights up, then shrinks toward the middle (to about 75 pt) and fades in 0.3 s.
- [O] It moves whatever Reduce Motion says.
- [?] Not measured: a navigation started while the last page is still loading. Cra goes back to the waiting pill
  until the new page commits, as Chromium treats it as a new navigation.
- Cra: LoadingIndicator (CraCore) has the numbers and the phase rule. CraBrowser.hasCommittedLoad is NO from each
  main-frame navigation (OnBeforeBrowse, not redirects) until OnLoadStart. LoadingIndicatorView draws it with Core
  Animation; a tab coming to the front shows its own state at once, without the widening or the finish. With no
  margin (edge to edge, fullscreen) there is no bar; on light themes it is black at the same opacities. It slides
  with the card when the sidebar hides or shows.

## A long wait for the first response (Arc 1.172.1, 8 Nov 2026, issue #256, offline copy)
Offline Arc (fake home, network limited to localhost), a new tab opened over AppleScript (`make new tab with
properties {URL:…}`) on a local server that answers after 40 s; window captures at 3, 6, 13, 20, 30 and 44 s.
- [O] While it waits: a white page, the tab row "Untitled", the address reading about:blank, × in place of reload.
  No status text, no notice; the frames at 13, 20 and 30 s are identical. The page appears when the answer comes.
- [O static] Arc's StatusTextController (`StatusText = statusText(String) | explainedStatusText(String, String)`)
  never showed Chromium's "Waiting for $1" load state in this run.
- Cra deviates on purpose (Victor asked for #256): ten seconds into the loading bar's waiting phase, Arc's toast
  (ShinyToast, so it shows edge to edge, in fullscreen and in a Little Window too) says "Still waiting for <host> to
  respond" with Stop Loading and ✕. It goes when the page commits, fails, is stopped or another tab comes to the
  front; ✕ holds for that navigation. SlowResponseNotice (CraCore) decides; CraBrowser.navigatingURL and
  navigationStarts (OnBeforeBrowse) give the host and restart the clock for a new navigation. Pinned by
  SlowResponseNoticeTests and the `slow-first-response` scenario (`${STALL}` never answers).
- [?] Not measured: whether Arc ever times out on its own (Chromium's network stack has no response-header
  timeout; the request waits for the server or a reset).

## Light and dark space themes (Arc 1.171, 3 Nov 2026, issue #155, Swift metadata + offline Arc)
- [O static] `WindowTheme.background` is `AppearanceBasedConfiguration<Background>`: `single(_0)` or
  `appearanceBased(light:, dark:)`; `semanticColorPalette` and `windowAppearance` use the same wrapper. The editor's
  state (`SpaceStyleEditor.State`) keeps `primaryColor`, `numberOfColors`, `wheel`, `intensityFactor`, `noiseFactor`,
  `lightnessRange` and `darkModeBiasSetting = .value(Double) | .forceAppearance(light|dark)`; the toggles send
  `didSetAutomaticAppearance` / `didSetLightAppearance` / `didSetDarkAppearance`. Strings: `sidebar-dark-mode-bias`.
- [O live] An `appearanceBased` space (this Mac's JYSK) shows its light half under View ▸ Appearance ▸ Light, its dark
  half under Dark, and the system's under Automatic, at once. Sidebar sampled at 2x: light 226/222/238 → 232/225/236,
  dark 40/37/54 → 44/37/55 (Cra: 233/227/245 → 246/234/240 and 45/39/57 → 47/39/57; the light half's gap is Cra's
  older pull toward white for opaque light themes, not this change).
- [O live] Opened on that space, the editor shows Auto with "Tap to pick a color for this space": the two-half theme is
  Arc's colourless default (base #C8CAFF / #FFE5E5 light at 0.5, #01021F / #1A001F dark at 0.8, key #8389FF). Both
  halves keep the key's HSL hue; the light one sits at HSL lightness ≈ 0.9, the dark one at ≈ 0.064.
- [O live] A swatch picked in Auto (offline Arc, menus and swatches pressed over AX: Spaces ▸ Edit Theme…, the swatch
  buttons "Set space color to Catalog color: … ColorPickerBrandN") was written as one `single` vibrant light theme; Arc
  writes StorableSidebar.json when the editor commits, not on every change. View ▸ Appearance is Arc's own
  `appearance` default (cleared again after the run) and also turns the editor's toggles.
- Cra: `SpaceTheme.dark` holds an Auto theme's dark half (top-level fields = light half) and `resolved(systemDark:)`
  picks one; `SpaceTheme.palette` resolves through `SystemAppearance` (NSApp.effectiveAppearance, observed), so a macOS
  switch redraws at once. Arc imports keep both halves. The editor builds halves from its pad (`SpaceTheme.key`) with
  `SpaceThemeVariants`: the light half is the pad's colours (lifted to HSL lightness 0.9 only when they read dark),
  the dark half darkens the light ones to HSL lightness 0.064 and draws them over neutral grey (#392, below). An
  Auto theme with one set of colours (saved before 0.1.29, or from Zen) stays on the side they suit whatever macOS
  shows, and an Arc `single` without `contentOverBackgroundAppearance` imports as that side (#171).
- Cra deviates on purpose (Victor, 6 Nov 2026, #155): the editor's Auto always builds both halves, one colour too.
  Arc saves a swatch picked on Auto as a fixed `single`; Cra copied that in 0.1.30–0.1.32, and a space set to Auto
  stopped following macOS. Pinned by `everySwatchOnAutoFollowsMacOS` and the `auto-theme` scenario.
- Cra (#300): the pad's − takes the last colour too, as Arc's does, and an empty pad saves that colourless theme
  (`SpaceThemeVariants.colourless`: the imported halves of Arc's default, both on Auto, one on Light or Dark) with an
  empty `key`, so the editor reopens on "Tap to pick a color for this space". Before, − stopped at one colour.
  Pinned by `noColourIsArcsColourlessTheme` and `padButtons`.
- [O live] How Arc treats a picked colour in dark mode (offline Arc 1.172, 12 Nov 2026, issue #392; editor driven
  over AX, StorableSidebar.json read after each commit, window captured): the editor's sun / moon toggles are Arc's
  app-wide View ▸ Appearance (the `appearance` default, NSAppearanceNameDarkAqua), not part of the theme, and AXPress
  on them is unreliable; set View ▸ Appearance ▸ Dark over AX instead. With Arc on Dark, every swatch was saved as
  itself in a `single` `blendedSingleColor` (black #000000, #1A1A1A, #333333, navy, white, red #F25E6B, pastel
  #F1D1EC), the intensity kept, `contentOverBackgroundAppearance` dark for dark colours and light for light ones.
  Arc never darkens a picked colour and adds no tint: on Dark a white or pastel space stays a light sidebar with dark
  text. Drawn as Arc's one-colour recipe (below, "Solid colour"), all neutral: black at intensity 0.25 over a light
  window read 122/121/123, at 1 read 43/43/44, at 0 156/155/157. Removing every colour deletes `windowTheme` (Arc's
  default space theme); its dark half read 36/36/55 → 41/37/54 on this Mac.
- [O fit] Arc's default dark half (non-vibrant, intensity 0.8): its top stop is 0.63 of #01021F (α for 0.8 in the
  one-colour recipe) over a neutral grey #5E5E5E (~94), within 1/255. The ~27 % over purple #2B2632 that
  ArcThemeImport uses was fitted on that purple theme alone and is locked for Arc imports (#155 tests).
- Cra (#392): the editor's dark half (Auto while macOS is dark, or Dark) keeps a colour that already reads dark
  (luminance < 0.45) as itself and darkens a lighter one to HSL lightness 0.064 in its hue (Arc's default pair,
  #8389FF → #01021F), and draws them neutral: one colour as Arc's one-colour fill at the slider's intensity
  (`solid`), a gradient opaque at that opacity over #5E5E5E. Before, every dark half went ~73 % over #2B2632 and
  ignored the slider, so black came out #2F2A36. Cra still darkens light colours where Arc keeps them light: Cra's
  Dark and Auto promise a dark look (#155). Pinned by `greysStayNeutralInTheDark`, `darkColoursKeepTheirOwnTone`
  and `darkGradientFollowsTheSlider`.

## The theme editor's presets and commit (Arc 1.171, 4 Nov 2026, issue #170, asset catalog + strings)
- [O static] The swatches are named colours in `ARCClients_BaseAssets.bundle`'s Assets.car (`assetutil --info`),
  four groups of nine: ColorPickerBrand1–9, Drab1–9, Pastel1–9, Greyscale1–9, defined in sRGB, extended linear
  sRGB or Display P3. As sRGB (what Arc writes to StorableSidebar.json; Brand8 saved as 0.4236, 0.7286, 0.8512):
  Brand #F2EAE4 #F29BBB #A6729D #F25E6B #FF8558 #F8D558 #34E895 #6CBAD9 #666789; Drab #4E3A5A #693558 #8F4042
  #B16D40 #D7B35D #CDCCA4 #7AA982 #226149 #26456B; Pastel #FEFBFA #FFE9F3 #F1D1EC #FFCBD1 #FFE0D3 #FFF9E5 #DEFDEB
  #DCF3FC #C5C6E5; Greyscale #FFFFFF #E6E6E6 #CCCCCC #B2B2B2 #808080 #666666 #333333 #1A1A1A #000000. The nine
  swatches sampled from captures on 1 Nov were these Brand colours as drawn (#E1686F for #F25E6B).
- [O strings] A swatch is a `colorSet` with `addComplimentary` (the preset view's fields), sent as
  `didSelectColorSet`; its AX label is "Set space color to Catalog color: … ColorPickerBrandN". The arrows are
  "Move to previous preset page." / "Move to next preset page." (`didTapPreviousPresetPage`, `presetCount`,
  `currentPresetPage`, defaults `currentThemeEditorPresetPage`). The editor state has an `undoStack` and a
  `didKeyDownEscape` action.
- [O live] Offline Arc, Spaces ▸ Edit Theme… over AX: all 45 swatches stay in the AX tree whatever page shows, in
  page order Brand, Brand, Pastel, Drab, Greyscale; the labels read "Set space color to Catalog color:
  #$assets-arcclients.BaseAssets.resources ColorPickerBrand4" (Pastel, Drab, Greyscale come from
  `arc.SpaceStyleEditor.resources`). Captures: page 2 is the Brand colours as two-colour gradients, page 4 Drab as
  single colours (not pairs, as #170 guessed from screenshots).
- [O live] A page-1 swatch (Brand4) changes the space at once without writing StorableSidebar.json; Escape closes the
  editor and writes it, keeping the change: one `single` vibrant light `blendedSingleColor` (0.949, 0.369, 0.420),
  intensity 0.8, noise 0. Closing by deactivating Arc writes it the same way.
- [O live] A page-2 swatch is saved as a `blendedGradient` with an `analogous` wheel: `baseColors` = [the Brand
  colour, a second one], `overlayColors` = [clear, a third one the other way round the wheel], vibrant light,
  intensity 0.8. The second colours for Brand1–9: #EFF1E3 #EFB19B #A6727F #EAAF5A #F0E941 #A4F454 #38E5E7 #7F7EDC
  #7F6589 (29–46° on in HSB hue, about the same saturation and brightness); Brand9's pair is a `dark` one. The
  turn isn't one fixed angle in HSB, OKLCH or Lab, so Cra keeps Arc's values (SpaceColorPresets.brandPairs).
- Cra: SpaceColorPresets (CraCore) holds the colours and pages; a pair is the colour and its complement
  (SpaceColorWheel.complement). One colour is saved as Arc's one-dot `single` theme (SpaceTheme.solid, on the side
  the colour suits); two or three as before. The Edit Space sheet shows the same card as Edit Theme Color…, and
  the list's right-click menu starts with Change Space Icon…, Rename Space…, Edit Theme Color… like the header's.
  Both preview every change without writing it (SidebarStore.previewTheme). Edit Theme Color… writes it when it
  closes (Escape, a click elsewhere, the app deactivating), as Arc does; the sheet writes it on Save and puts the
  stored theme back on Cancel.

## Little Arc: Copy URL and Shift-click (Arc 1.171, 3 Nov 2026, X DM, offline Arc)

An offline Arc (fake home, no network) with a Little Arc on a file:// page, ⇧⌘C and a Shift-click sent as HID
events, the window recorded with `screencapture -V`.
- [O] ⇧⌘C shows Arc's toast, "Copied Current URL" with a share glyph button, springing in from the top over the
  "Open in" button and settling 8 pt under the window's top and ~8 pt in from its right edge, 42 pt tall, over the
  toolbar. The link glyph itself doesn't change. Fill (sRGB, from Display P3) 41/18/77 at the top → 33/16/61, outline
  33/14/66, white text, darker than the default dark theme's toast in a browser window. Cra: the same ShinyToast,
  `LittlePalette.toast`. The share button isn't reproduced (not checked whether a browser window's copy toast has it).
- [O] A Shift-click on a link in the Little Arc's page opened it in that Little Arc: no Peek, no second window
  (AX and CG window lists before and after). Cra used to open another Little Window. A Shift-clicked link in a
  browser window still opens a Peek (`shiftClickModalEntryPointEnabled`).

## Little Arc's profile (Arc 1.171, 4 Nov 2026, issue #172, Swift metadata + strings + assets)

- [O static] `LittleBrowser.State` holds `profile: Profile` and `shouldShowProfileIndicators: Bool`;
  `LittleBrowserCreationProfileType = profile(Profile) | lastUsedProfileFromStandardWindow`, and the window
  record keeps the profile (`little { profile: … }` in StorableWindows.json, above). So a Little Arc gets
  the profile of the window used last when it opens and keeps it; "Open in <space>" follows the window used
  last separately (issue #92).
- [O static] The toolbar's ViewState has `profileName: String?`, drawn as `URLField.Accessory.profileIndicator
  {profileName, onClick}` in the address field (AX id `littleBrowserProfileIndicator`) by ProfilesUI's
  `ProfileIndicatorView` (`ProfileIndicatorConfig {profileName, tooltip, theme, size condensed|full,
  showsChevron}`, icon `profile` = the "archie" smiley, or `incognito`). Fill `ProfileIndicatorBackgroundColor`:
  white at 31/255 in dark, #181B1F at 18/255 in light.
- [O static] A click is `LittleBrowserToolbarAction.showChangeProfileMenu(mouseLocation:)`: a menu of
  `ChangeProfileMenuOption {profile, isCurrent}` ("Caption for Little Browser menu to change the current
  profile"). Picking one is `onClickChangeProfile(Profile)` → `ProfileDialogUtils.MoveKind.changeProfileInLittleWindow`,
  a confirm with "Each Profile has different browser data, so this webpage might look a little different." and
  "Don’t ask again" (`shouldBypassConfirmLittleBrowserProfileDialog`; decisions abort | proceed | alwaysProceed),
  then `LittleBrowser.Action.setProfile`.
- [U] Not seen live: the offline copy's Little Arc opened as a 490 × 329 card that didn't load a typed file://
  address, and the Arc lock was wanted by other sessions. The dialog's title and button names, the chip's exact
  geometry and whether ⌘O into a space on another profile asks first (`MoveKind.to`, "… is using a different
  Profile, so you might get logged out or lose your progress in …", `shouldBypassConfirmInterProfileMoveDialog`)
  are still open.
- Cra: `LittleWindowState.profileID` (set when the window opens, kept), `LittleProfileChip` in the pill left of
  the extensions button (the tooltip pill's 22 pt metrics, white 31/255), the menu Default | profiles with the
  page's ticked, an NSAlert with that text and "Don’t ask again" (defaults
  `shouldBypassConfirmLittleWindowProfileDialog`), then the page reloads in a new browser in that profile.

## Peek and the copy toast's Share button (Arc 1.171, 3 Nov 2026, offline Arc)

Offline Arc in a 1728 × 1084 pt window (sidebar 347 pt), a page that is one big link, Shift-click as a HID
event with `shiftClickModalEntryPointEnabled` set for the run, AX frames and 60 fps recordings.
- [O] With `shiftClickModalEntryPointEnabled` unset (Victor's defaults), a Shift-click on a file:// link opened a
  new tab below, not a Peek. With it on, a Shift-click on an https link opened the Peek.
- [O] The Peek is a card in the browser window: x 485…1590, 12 pt in from the window's top and bottom, i.e. 80 %
  of the area from the sidebar's edge to the window's right edge, centred on it. 8 pt continuous corners, a soft
  shadow. It has its own 32 pt bar (back, forward, refresh from the card edge, the address centred with its
  copy-link glyph, "example.com/peek", host then dimmed path), white while the page had no colour.
- [O] Beside it, 13 pt right of the card, a column of 34 × 33 pt round buttons 7 pt below its top, 43.5 pt
  apart: `confirmCloseModal` "Close ⌘W" (xmark), `openInSpaceExpander` "Expand ⌘O"
  (arrow.up.left.and.arrow.down.right), `openInSplit` "Add To Split" (square.split.2x1). Fill 16/13/0, glyph
  250/238/194 on the fake home's yellow space: the space's tooltip fill (shadedDark at 30 %) and its light
  foreground. Their tips are the space's ArcTooltip.
- [O] The page behind fades to about 28 % over the window's background (233/240/254 → 178/172/151); the sidebar
  stays. Opening and closing: see "Peek grows out of the link" below. This run's page was one big link, so the
  card seemed to start at the area's full size and to go back out to it.
- [O] "Copied Current URL" carries a Share glyph button in browser windows too (AX `square.and.arrow.up`, "Share",
  31 × 27). The toast is 195 × 47 pt: text 13 pt in, 14.5 pt to a 29 × 27 pt button 13 pt from the end, 10 pt from
  top and bottom. The button is a white wash over the pill (≈ 60 % on the light toast, 15 % on Little Arc's dark
  one) with an outline. A click opens the macOS share menu (AirDrop, Notes…) from the button; the toast stays.
- [O] The motion from that page-sized link, frame by frame at 60 fps (card edges on one row, the card's and the
  page's luminance): opening, what read as the card's opacity reaching 1 in ~0.075 s was the link's picture (the
  whole page) fading out over it; its scale went from the whole area (1.25, centred) to 1 on an ease-out cubic
  over ~0.205 s (scale − 1 per frame: .168, .127, .092, .063, .041, .025, .015, .008, .002). The page fades on an
  ease-out cubic over ~0.18 s. Closing: the card grew to ~1.19 in ~0.09 s (near linear), "fading" from ~0.07 s
  (the link's picture coming back), gone by ~0.16 s; the page is back after ~0.2 s.
- Cra draws the motion on Core Animation (PeekTransition): pictures of the card (with Chromium's screenshot of
  the page when closing) and of the buttons in a panel over the window, the real card and buttons invisible at
  their places until it lands. Animating the windows' frames (the first version) resized and laid out the card
  and its page window on every frame and stuttered; Chromium also sets its page window's alpha back to 1 as it
  shows it, so the page waits hidden (contentView.isHidden), not transparent.
- Cra: PeekLayout (CraCore) has the geometry; PeekBarView and PeekControlsPanel (PeekChrome.swift) the card's bar
  and the buttons; MainWindowController.setPeekVeil fades the page; ShinyToast.Action.share the button.
- [S, 12 Nov, GitHub #385] The buttons' hover and press, from Arc 1.172.2's arm64 code (no symbols: the body
  witness of `ModalButtonStyle.ButtonView: View`, found through the conformance's resilient witnesses, then lldb
  on the file). `ModalV2ControlButton` uses `ModalButtonStyle` (fields `buttonFill`, `buttonAccent`; its
  `ButtonView` holds `isPressed` and `@State isHovered`). The body is: the label in the accent, padding 8, clipped to
  the capsule, on the fill with `.shadow(color: .black.opacity(isHovered ? 0.3 : 0.2), radius: isHovered &&
  !isPressed ? 6 : 4, x: 0, y: 1)`, `.offset(y: isHovered ? -1 : 0)`, `.animation(.spring(response: 0.15,
  dampingFraction: 0.95), value: isHovered)`, `.onHover`, `.scaleEffect(isPressed ? 0.95 : 1)` about the centre,
  `.animation(.spring(response: 0.28, dampingFraction: 0.63), value: isPressed)`. The fill doesn't change.
  `ModalControlState.dismissButtonScale` (a `@Published` CGFloat) scales the Close button in
  `ModalV2ControlsViewSwiftUI` on `.spring(response: 0.25, dampingFraction: 0.8)`, but its key path pattern is
  used only by that read and its own accessor thunks: nothing in 1.172.2 writes it, so ⌘W doesn't animate the
  button in Arc. Not seen live (Arc runs one instance; a Peek needs a click in Victor's Arc).
- Cra (#385): PeekControlLook (CraCore) has those values and springs as Core Animation takes them (stiffness
  (2π / response)², damping 4π · fraction / response); PeekControlButton draws its fill, shadow and glyph on its
  own layers so the press can scale about the centre. Past Arc, at the reporter's request: ⌘W and ⌘O press their
  button (PeekControl.pressed(byAction:)) for 0.15 s on the press spring while the action runs at once. Close's
  closing picture, taken within 80 ms, carries the pressed button; Expand's Peek is gone that frame.
- [O, 4 Nov] Which links peek, with both Links settings on (`modalEnabled` and
  `shiftClickModalEntryPointEnabled` set for the run, the sidebar reset before each run), HID clicks on a
  lab page at 127.0.0.1 in a pinned tab: a link to localhost peeked, plain or target=_blank; a link to
  127.0.0.1 loaded in the tab, but with target=_blank it peeked, and so did window.open to localhost; a
  ⌘-click opened a background Today tab. A Shift-click peeked, same host or not, also from a Today tab.
  With `modalEnabled` unset (Victor's defaults) the pinned tab's link to localhost opened a new tab.
  Cra: PeekTrigger (CraCore).
- [O] Inside the Peek, links to either host loaded in the Peek. A click on another sidebar row closed the
  Peek and opened that tab. ⌘W closed it, and ⇧⌘T right after brought the Peek back over the pinned tab.
  ⌘O and Expand made it a tab at the top of Today. Add To Split from the pinned tab left the pinned tab
  where it was and put a new split at the top of Today: a copy of the pinned page ("Lab") on the left,
  the peeked page on the right. Cra: MainWindowController.closedPeek, LittleWindowController.promoteToSplit.
- [?] Not measured: the card at other window widths (Cra keeps 80 % of the area), and the Peek with Arc's
  toolbar turned off.
- [O, 6 Nov, GitHub #202] A target=_blank link clicked inside a Peek (HID click, offline Arc, Peek opened by a
  Shift-click from a Today tab on a 127.0.0.1 lab page) closed the Peek and opened the page as a new Today tab
  in the same space, selected, right below the tab the Peek came from. No second Little Arc or Peek, and the
  peeked page was not kept as a tab. Cra (0.1.31) opened another Little Window. Cra: PeekTrigger.leavesPeek,
  LittleWindowController.openTabFromPeek → BrowserManager.openLinkTab (the placement links from a tab get, so
  from a pinned tab the top of Today). Not observed in Arc: a ⌘-click inside the Peek (Cra: a background tab,
  the Peek stays) and window.open with features (Cra: still a Little Window over the Peek, which keeps the
  opener alive for sign-ins).
- [O static + reported, 8 Nov, GitHub #242] A Peek belongs to its tab. Arc 1.172.1's
  WindowContents/WindowContentState keeps `modalByWindowContent` (next to `presentationState`,
  `sourceToWindowContentMap` and `windowContentSidebarItemMap`), a modal per window content, and the
  reporter (Arc 1.172, daily use) sees the Peek a target=_blank link "closed" there again, same page and
  scroll, back on its pinned tab. So the 6 Nov run above saw the Peek go out of sight, not end. Cra:
  PeekPresence (CraCore), MainWindowController.syncPeeks → LittleWindowController.parkPeek /
  unparkPeek / dropPeek; the tab's row keeps the peeked favicon while the Peek waits (modalIcon).
- [O live, 8 Nov, GitHub #242] Checked in offline Arc 1.172.1 (fake home, one space, pages on pin/away/other
  .lvh.me:47139 that report load, scroll, visibility and pagehide to the server, HID clicks at 2x, a 60 fps
  recording). From the pinned tab: its link peeked, the peeked page scrolled itself to 1234; the Peek's
  target=_blank link opened a selected Today tab and the peeked page went `hidden`, alive (no pagehide).
  A click on the pinned row brought the same page back (same instance, never reloaded) at 1234.
  - A click on another sidebar row with the Peek on screen only hides it too: that tab opens, the peeked
    page goes hidden, and the Peek is back with its tab. The 4 Nov "closed the Peek" was this.
  - A Peek from a Today tab (Shift-click) waits the same way; its target=_blank link put the new tab right
    below its tab. Both rows showed the badge at once.
  - Coming back: the card is there whole in one frame (one blank frame while the page repaints), no
    grow or fade; only the dimming behind it eases in, ~5 frames (~80 ms). Cra: at once.
  - The background pinned row with a Peek waiting on it shows ✕ (Archive this tab) on hover, being on its
    page, and archiving it ended the Peek (pagehide). A pinned tab with a waiting Peek is never away from
    its page, so the minus (Close and Keep Pinned) and ⌘W don't meet a waiting Peek; ⌘W with the pinned
    tab open closes the Peek on screen (4 Nov). Cra: archiving drops the Peek; a pinned ⌘W drops it too.
  - Cra: the click catcher (PeekDimPanel, PeekLayout.dismissArea with `contentMinX`) covered the sidebar,
    so a row click closed the Peek; it now covers the page area only and the row's tab opens (syncPeeks
    parks the Peek). cra://debug?peekCatcher reads it.
  - [?, 9 Nov, GitHub #295] With the sidebar hidden, the sidebar that slides out at the edge came out behind a
    Peek and its click catcher in Cra (raiseOverlayPanels put the Peek last). Not measured in Arc, whose Peek is
    a card inside the window under its floating sidebar. Cra now stacks the floating sidebar above the Peek's
    windows; cra://debug?peekCatcher reads `floating=above|below|none` from the window server's order.

### A Peek's favicon on its favorite tile (Arc 1.172.2, 12 Nov 2026, GitHub #381, static)
- [S] The favorite tile's model, `AppItem` (and its unnamed sibling with `childItems`), has
  `badgeIcon: NSImage?` next to the pinned row's `modalIcon: NSImage?` (`__swift5_fieldmd`, arm64 slice).
  `AppTrayItemViewAppKit` keeps a `badgeView: AppTrayItemBadgeView?` (file
  AppTray/AppTrayItemBadgeView_AppKit.swift), an NSView with one lazy `iconView` (NSImageView). The
  tiles' unread mark is a different thing (`AppTrayItemOverlay.badge: NSColor`, a dot). The reporter
  saw Arc put the peeked page's favicon there while a Peek from the favorite is open.
- [S] Geometry, from AppTrayItemViewAppKit's `layout` (0x101d19b3c): the badge's frame is
  (width − 10 − 6, −4, 20, 20) in the flipped tile, so it sticks out 4 pt past the top and the right edge;
  its layer gets anchor (0.5, 0.5) and the same frame again.
- [S] AppTrayItemBadgeView: `layout` puts the icon at (midX − 8, midY − 8, 16, 16), backing-aligned
  (NSAlignAllEdgesNearest). `updateLayer`: masksToBounds NO, corner radius 6, continuous corners,
  background the asset colour `FullOpacityBackgroundPrimary` (ARCClients_BaseAssets: sRGB white, black in
  Dark Aqua), shadow black, opacity 0.25, radius 4, offset (0, 1.5). The tile adds it with
  `setImage:` on the icon view and animates `transform` (from scale 0.1 about the centre) and `opacity`
  with a CASpringAnimation built from response 0.4 and damping ratio 0.6 (stiffness (2π/0.4)², damping
  4π·0.6/0.4), both ways.
- Not seen live: Arc 1.172.2 runs one instance, and opening a Peek from a favorite needs a real click in
  Victor's own Arc. Cra: FavoritePeekBadge (SpaceColumnView.swift), fed from SidebarUIState.peekBadges, the
  same entries the pinned row's badge reads, so it stays while the Peek waits and goes with it.
  cra://debug?favoriteBadges reads it; scenario favorite-peek-badge.
- Cra trap: on macOS 26 setting an NSView's `layer.cornerRadius` turns `clipsToBounds` on, which cut the
  badge to the tile's rounded corner. The badge turns it off after its radius; the tile turns it off only
  while it wears a badge, since `layer.render(in:)` (component snapshots) draws an unclipped corner radius
  without anti-aliasing.

### Peek grows out of the link (Arc 1.171, 6 Nov 2026, GitHub #204, offline Arc)
The reporter recorded Arc 1.172.1 growing the card out of the clicked link. 1.172.0/1.172.1 only moved Chromium
(appcast notes: "no other changes"), so this was measured on 1.171 with a lab page on 127.0.0.1: two 68 × 31 pt
links, A near the top left and B near the bottom right, real HID Shift-clicks (`modalEnabled` and
`shiftClickModalEntryPointEnabled` set for the run), Escape to close, an app-only ScreenCaptureKit recording at
60 fps, the card's frame and a black box inside the peeked page measured per frame.
- [O] Opening: a picture of the link fills the moving frame (stretched, opaque) and fades out over the card on an
  ease-out over ~0.075 s (red over blue reads 0.40, 0.21, 0.065, 0.02 a frame apart). The frame goes from the
  link's rect to the card's: its centre (x and y) and width on an ease-out cubic over ~0.205 s, the height
  lagging on an ease-out cubic over ~0.21 s about 12 ms later (when the width was 60 % of the way the height
  was 48 %; frames from link B gave the same pairs). The page inside is a picture scaled by the frame's width
  against the card's, pinned to the frame's top-left; the frame (8 pt corners) clips the rest.
- [O] The buttons ride the frame's top-right corner, scaled like the page, 7 pt below its top, and fade in once
  the link's picture is gone (none at ~0.055 s after the motion starts, faint at ~0.08, full by ~0.13).
- [O] Closing from link B: the frame goes back to the link's rect on the same near-linear curve as before, over
  ~0.16 s (fit on 6 frames: .13, .31, .49, .64, .80, .88), the card opaque, the link's picture fading back in
  over it from ~0.07 s (≈ 0.3 at 80 % of the way, 0.55 at 88 %); then only the real link. The buttons go in
  ~0.05 s.
- [O] Closing from link A went back into link A the same way (.09, .26, .44, .66, .78, .86, .92 a frame apart,
  the link's red fading in over the blue). Only the very first Peek after launch (Arc's toolbar grew 8 pt during
  that run) shrank about its own centre instead and faded out in ~0.07 s; taken as a first-run glitch.
- Cra: PeekLayout.opening / closing / content / column (CraCore) sample the motion; PeekTransition plays it as
  Core Animation keyframes at 120 Hz. MainWindowController.peekSource finds the link under the pointer (else
  the focused link) with a script in Cra's isolated world and cuts its picture out of Chromium's screenshot,
  within 90 ms. The script looks inside open shadow roots (Reddit's post links, GitHub #359). When it finds no
  link but a mouse button went down on the page under a second ago (a closed shadow root, another site's
  frame, a page too busy to answer in time), the card grows from a 20 pt square at the click, fading itself,
  and closes back there (PeekLayout.origin). With neither (or in a WebKit tab) the card grows from the whole
  area and fades itself, as from Arc's page-sized link. Closing asks where the link is now (the page may have
  scrolled) and goes back there; out to the whole area when it's gone. Recorded the same way in a test copy: the card's left edge went .65,
  .77, .84, .91, .93, .98 of the way a frame apart (Arc .60, .77, .85, .91, .95, .97), its bottom edge .34,
  .59, .71, .80, .87, .91 (Arc .31, .54, .73, .82, .89, .94), and it closed back into the link.

### Peek, the window's shadow and its edges (Arc 1.172.1, 6 Nov 2026, PR #222, offline Arc)
Offline Arc (fake home, network blocked) in a 1100 × 760 pt window at 100,80, a Peek opened by a HID
Shift-click on a lab page's link, then HID clicks and drags; Peek open or closed read from AX (its Close button,
`confirmCloseModal`), the window's state from AX and `screencapture -l` with the shadow.
- [O] The Peek is a card inside the browser window: no second CGWindow or AX window while it shows (the
  `ModalContent.ModalWindow` class is a plain NSWindow subclass with no focus overrides, but none was on
  screen). The browser window stays main and keeps its full shadow, before and after a click into the
  Peek's page (capture 2424 × 1744 px both times).
- [O] Clicks near the edge, outside the card: 1–3 pt inside the right or bottom edge and 1–2 pt inside the
  top keep the Peek (macOS's resize band takes them); 4 pt in (3 at the top) closes it. Left: the sidebar
  is there, and 1–6 pt in kept it.
- [O] A drag from 2 pt inside the right edge, or 2 pt below the bottom edge, resizes the window with the
  Peek open, and the card grows with the window.
- [O, Cra] 0.1.32 lost the browser window's active look as soon as a Peek opened (grey traffic lights,
  capture 2336 × 1656 px): Chromium keeps only the child windows it made itself from becoming main
  (-[NativeWidgetMacNSWindow canBecomeMainWindow]), and the Peek's page window hangs on Cra's window
  through AppKit. Its click catcher covered the whole window, so every click 1–12 pt in closed the Peek
  and a drag from 2 pt inside closed it instead of resizing (from outside it resized).
- Cra: ChromiumChildFocus keeps a Peek's or Little Window's page from becoming main; PeekDimPanel covers
  PeekLayout.dismissArea, the window minus a 3 pt band. Checked on a test copy like Arc above: full shadow
  and coloured traffic lights after a click in the Peek, edge clicks 1–3 pt in keep it and 4 pt in close it,
  and a drag from 2 pt inside resizes with the Peek open.

## Capture (Arc 1.171, 4 Nov 2026, X request, Swift metadata + strings + offline Arc at 2x, 120 fps recordings)
- [O metadata] Module `Capture`: ContentCaptureViewController holds ContentCaptureView (grayscale and darkened layers with
  shape masks, a lens ShadowView, a camera cursor view, single/double click and pan recognizers, an Esc monitor,
  `FocusRectAnimator` = a Motion spring on the rect plus `lensOpacity`), ContentCaptureOverlayBubble, CapturedImageView
  and CapturedImageActionsView (a SwiftUI menu). Actions (`CaptureImageMenuView.Item.ContentType`): easel(String),
  newEasel, copy, library (toggle), saveAsFile, sendAsMessage, edit, retake. `CaptureType` partialPage / fullWindow
  (the "pretty screenshot" with wallpaper/tint/watermark is fullWindow). Captures are kept in StorableCaptures.json for
  the Library's Media.
- [O strings] Click-to-capture picker (JS, `elementsFromPoint`): score each element under the pointer: −5 if its smaller
  side < 100, −5 if as wide as the window, −5 if as tall, −5 if over 70 % of the window's area, +5 for IMG/PICTURE/OBJECT,
  + (w + h) / 2 / 500, −10 if `display: inline`; keep scores ≥ 0, take the best. Live: over a 3-card grid it picked the
  grid; text, a full-width header and a taller-than-window block got nothing (bubble then says "Drag…").
- [O live] ⇧⌘2: the page (not the toolbar or sidebar) turns greyscale under a 25 % black veil in ONE frame:
  value = 0.75 × Rec. 601 luma of the stored sRGB values (243,241,235 → 181; 212,73,76 → 86; 79,155,143 → 98; within 1).
- [O live] Lens: the element shows in colour 2 pt beyond its edges with 4.5 pt corners, inside a 4 pt ring #161C2F
  (outer corners 8.5 pt), and a soft shadow outside it (~26 pt falloff, a few pt low). A dragged rectangle gets the ring
  right outside it (no 2 pt clearance). Moving between elements the rect springs: ~0.15 s to arrive, 0.4 % overshoot,
  settled by ~0.2 s (≈ stiffness 2000, damping 78, unit mass).
- [O live] Bubble: white 354 × 65 pt, centred on the page, its bottom 36.5 pt above the page's bottom, ~17 pt corners,
  a 1 px pink → blue rim, "Click or drag to capture a portion of this page" / "Drag to capture a portion of this page"
  in 14 pt semibold OverlayBubbleText (#3405 94, reads ~78 %). Around it a dark tinted glow (163 grey → 155,147,148 left,
  140,143,156 right, gone ~90 pt out), slowly moving. It fades in over ~0.16 s.
- [O live] Pointers: a dark camera with a white outline over a clickable element; a crosshair with the camera at its
  top right elsewhere and while dragging.
- [O live] A first-time tip at the top right: "Next time, hold ⇧⌘ and drag your mouse to capture any time."
- [O live] After a drag: the capture stays lit with its ring; a menu 273 × 354 pt, 4.5 pt right of the ring, tops level,
  ~10 pt corners, fill (18,15,44) (Background, dark) even on a light theme: "Send To…" field (13–42.5 pt, white 7 %),
  rows 40 pt apart (Save to Library ○, Copy, Save…, Send via iMessage…), hairline, Edit, Retake, hairline, New Easel.
  Symbols 30 % white centred 25 pt in, 14 pt medium text 90 % white from 41 pt; hairlines 10 pt in from both sides.
  The partial capture does not touch the clipboard by itself. First Esc left the menu up, the second ended the mode.
- [?] A scripted HID click on an element did not capture (no menu after 0.6 s), so the click result, Copy's toast text
  and Retake were not observed. Arc's strings have "Confirmation toast when copying a captured image" (text inline).
- Cra (CaptureOverlay, ContentCapture in CraCore): the same mode over a Page.captureScreenshot picture in a panel over
  the page; picker run in Cra's isolated world; Copy / Save… / Send via iMessage… / Retake (no Easels, Library Media or
  Edit in Cra); Copy shows "Screenshot Copied to Clipboard"; the macOS screenshot sound plays when a capture is taken.

## Pinned extensions with the toolbar hidden, and in a narrow toolbar (Arc 1.171, 4 Nov 2026, X report, offline Arc)

Offline Arc as in "One space", with 11 of Victor's extensions copied into the fake home's Default profile
(`Extensions/<id>` plus his `Secure Preferences` wholesale, so the MACs stay valid) and
`extensions.pinned_extensions` set in its Preferences. Traps: the space must be on the profile that holds
the extensions (the fixture's "Side" space was on Profile 1 and showed none); ModHeader never loaded.
Sidebar width via StorableWindows' `sidebarWidth`, window size over AX. Frames from AX dumps.

- [O] URL field in the sidebar (`topBarURLEnabled` NO). While the pins leave the address room they go in
  the URL field, shown on hover after the address and before Copy Link and Site Control Center: 30 pt boxes,
  one every 28 pt, Site Control Center's box ending 4 pt in from the field's end (240 pt sidebar, 3 pins:
  1Password, JSON Formatter, Lighthouse at x 86, 114, 142, Copy 170, Site Control Center 198). The host
  truncates under them (7 pins at 347 pt: "github.co").
- [O] With more, they leave the field (which keeps Copy Link and Site Control Center only) for a grid of
  their own, shown all the time: the first section of `sidebarFavoritesCollectionView`, 8 pt in from both
  sides and 8 pt under the URL field, the favorites 8 pt under its last row. Cells 28 pt tall, 8 pt apart
  both ways, spread over the width: like the favorites grid, as many columns as keep a cell at least
  ~28 pt wide (no cap seen: 7 in one row at 270 and 300 pt), then the fewest that need no more rows.
  11 pins: 4 + 4 + 3 at 200 pt (cells 40 wide), 6 + 5 at 240 (30.67), 300 (40.67) and 347 (48.5).
  5 at 200 pt: one row of 30.4. Icons 18 pt, centred.
- [O] Field or grid (github.com in the field), by field width (sidebar − 16) less 28 pt per pin:
  in the field 3 @ 240 (140 left), 4 @ 252 (124), 4 @ 262, 5 @ 300 (144), 7 @ 347 (135);
  grid 4 @ 240 (112), 4 @ 245 (117), 5 @ 200, 7 @ 270, 300, 320 (108), 8 @ 347 (107), 11 everywhere measured.
  The cut is between 117 and 124 pt; Cra keeps the pins in the field while that leaves at least 120
  (PinnedExtensionGrid.fieldReserve).
- [O] The field's Copy Link and Site Control Center show while the pointer is anywhere over the sidebar
  (a point 600 pt down the tab list showed them), not only over the field. Cra still shows them for the
  header only.
- [O] Toolbar on (`topBarURLEnabled` YES): every pin in the toolbar at 1728 pt and no grid. Narrow windows
  keep the address whole and centred and hide pins from the front of the list: ten pins, the last seven
  at 1100 pt, the last two at 800 pt (`numberOfExtensionsThatFit`, `urlDomainHasRoom` in the content
  toolbar's layout). Cra: ToolbarExtensionFit in PaneToolbarView.layout, against Cra's own address
  room (centred between the button groups, not in the card as Arc's), so the cut can be a pin off Arc's.
- [?] Not measured: whether the switch depends on the host's width (only github.com was tried), the grid
  cells' hover and pressed fills, where a grid pin's popup opens (Cra: under the cell), a space with
  pins but no favorites (Cra: the header follows the grid as it follows tiles).

## Tidy Tabs (Arc 1.171, 4 Nov 2026, Swift metadata + strings, Victor's Arc with Arc Max on, offline Arc at 2x, 120 fps)

Arc Max's "Organize Today Tabs". Arc sends the loose Today tabs to its server (OpenAI) and files them under
named group headers; Cra asks the Mac's own Apple Intelligence model instead (Victor, 4 Nov 2026: only when
Apple Intelligence is on, so it's free and nothing leaves the Mac).
- [O static] `tidyTabsEnabled` (defaults), `canAutoOrganizeTodayTabs`, `createUnpinnedTabGroups()` in
  WindowData+TabGroups.swift with the request "Here are my tabs, in the format 'id: title':" and "Your array
  of group assignments, as valid JSON within a ```code block```:" plus a "Tab group of miscellaneous tabs".
  The answer becomes `SidebarItemData.tabGroup(SidebarTabGroup { title })` items in the unpinned container,
  the tabs their children: in StorableSidebar, `"data": {"tabGroup": {"title": "Planets"}}` (an empty `{}`
  fails to decode and Arc drops the item with its tabs). Undo string "Undo prompt for tidying explore tabs".
- [O static] UnpinnedSectionHeaderCellView: stackView, tidyButton (SidebarTidyButton: imageView "broom-stick",
  a 14 pt template SVG in ARCClients_BaseAssets, label, divider), clearButton, downArrowImage, borderView,
  squiggleView. SquiggleDivider (viewModel, height, amplitudeAnimationDuration) over SquiggleViewModel (period,
  phase, controlPointFraction, amplitudeFunction); window state `dividerSquiggleActiveSpaceIDs`.
- [O] Shown on hovering the divider once Today holds 6 tabs, grouped ones counted (offline: 5 loose tabs →
  Clear only; 6 → Tidy; 2 loose + 6 grouped → Tidy). Tooltip "Organize Today Tabs". After a run Tidy is
  gone until Today changes, even when the run grouped nothing (Arc's server no longer answers: a click gave
  0.57 s of squiggle and no groups; a second click on that spot did nothing).
- [O] Layout at 2x on a 347 pt sidebar (dark space): the line ends 239, broom ink 248.5–257, "Tidy"
  262–282.5 (11 pt semibold, the Clear label's tone, brighter on hover), a 0.5 pt hairline 12.5 pt tall at 291,
  "Clear" 302–327.5.
- [O] The squiggle (60 fps, sine fitted per frame): period 12.75 pt, amplitude 3.0 pt the whole length of the
  line, travelling left at 5 periods a second (phase +0.52 rad per 1/60 s); the amplitude ramps linearly 0 → 3
  in 0.4 s from the click and back in 0.4 s when the answer is in.
- [O] The broom turns about the top of its handle: 31° clockwise in ~0.2 s (ease out) at the click, holds
  ~0.12 s, swings back 7° past upright by ~0.65 s and settles by ~0.9 s. Only one sweep was seen (the run
  ended); Cra repeats it while the model works.
- [O] Group header (offline Arc, hand-written tabGroup items): a 41 pt row like a tab's, no icon, the name in
  13 pt semibold in the space header's tone at the tabs' icon inset (x 17); the tabs below are not indented.
  Hovered, two 26 pt buttons end 13 pt in: `folder.badge.plus` "Create Folder" and ✕ "Close tab group"; no
  row fill. Right-click: one item, "Remove header" (the tabs stay where they are, loose). Create Folder: an open
  folder with the group's name at the top of Pinned, its tabs inside and pinned; the group goes.
- Cra: TidyTabs (CraCore: when to offer, the prompt, cleaning the model's answer, Today's order),
  TidyTabsService (FoundationModels guided generation, macOS 26, hidden without Apple Intelligence),
  SidebarStore tab groups (a folder with `tabGroup: true`, so an older Cra reads the file), DividerRowView's
  TidyButton + SquiggleLayer + BroomGlyph (Cra's own drawing of the broom), GroupHeaderRowView. ⌘Z undoes the
  last tidy until a tab closes or a header is used. Measured on Cra: amplitude 2.97 pt, +0.52 rad a frame,
  ramps 0.38 s.
- [?] Not seen: Arc's real grouping (the server is gone), what Arc does with a model answer naming an existing
  group, whether a header can be dragged, and the arrow Arc sometimes draws before "Clear" (offline copy).

## Tidy titles and Tidy Tab Titles (Arc 1.171, 4 Nov 2026, Swift metadata + strings, Victor's Arc, 60 fps recordings)

Two things share the name. Arc tidies every tab's displayed title by per-site rules, always; Arc Max's Tidy Tab
Titles (`renamePinnedTabsEnabled`, AI endpoint `renamePinnedTabs`) gives a tab a new name when it is pinned.
- [O] Rules: `tidyTitles` in web_content_behavior.json (ARC_WebContentBehaviorConfigurationClient.bundle, also
  served by content.arc.net): 52 sites (51 online, less app.notion.com), each `{siteName, rules: [{match?, title}]}`.
  `match`: pathEquals, pathContainsRegex, fragmentEquals, fragmentContainsRegex (none: everywhere); `title`:
  always, removingPattern, removingPatterns (decoder strings next to "Unable to decode TitleModifier"). Live:
  "Jupiter - Wikipedia" shows "Jupiter", "Y Combinator | Hacker News" "Y Combinator", "Climate - BBC News"
  unchanged (no rules), the same with renamePinnedTabsEnabled off. Stored savedTitle stays the page's.
- [O] Tidy Tab Titles, live (two pins, Tabs ▸ Pin Tab): "Foundation Models | Apple Developer Documentation" →
  "Foundation Models", "Climate - BBC News" → "Climate News". Stored as the item's custom `title`. Arc's server
  still answered on 4 Nov 2026 (Tidy Tabs' didn't).
- [O] Timeline (60 fps): the row moves into Pinned in ~0.12 s; the rename starts 0.95–1.07 s after the pin (the
  server's round trip). At once the row turns two-line: title up, "Double-click to rename" under it (Arc's
  TabCellState hint, also the hover tooltip's subtitle). One soft front (~72 pt from opaque to clear) crosses
  left to right at ~1,180 pt/s: the old title (drawn whole, clipped, no ellipsis) fades out behind it, the new title
  and the subtitle in; the subtitle is bright (white ~96 % on the dark space) until the end. Sparkles: white dots
  ~1.5–3 pt, ~28 at a time, rising along a band that crosses the whole row in 0.55 s, scattered up to ~30 pt above
  and below it, mostly lit until the end. At 0.55 s (0.525 and 0.55 measured) sparkles go at once and the
  subtitle drops to its usual tone; it leaves 3.1 s later (in ~0.07 s), the row back to one line.
- [O static] TabCellView: isAnimatingAiRename, animatedGradientView (AnimatedGradientView: oldView, newView,
  baseMaskLayer, overlayMaskLayer, animationDuration, animationDelay, fadeWidth, contentOffset), sparksView
  (sparkles, animationPeriod, animationDuration, sparkleColor), currentSubtitleAnimationUUID. Analytics
  `auto_renamed_pinned_tab` with old/new title length.
- Arc's earlier renames in Victor's sidebar (the model's examples): "IT Career Paths - IT General - Confluence" →
  "IT Career Paths", "Personal apps | Heroku" → "Heroku", "Deltagere ‹ Grønne tanker — WordPress" → "Grønne tanker".
- Cra: TidyTitleRules (Arc's rules data, every unnamed tab row and split cell), TidyTitles + TidyTitlesService
  (FoundationModels, ~0.5 s, held to ~1 s after the pin like Arc), TabRowView.playTidyRename (front masks on the
  old and new title and the subtitle, 46 sparkles). Measured on Cra: rename 1.08 s after the pin, 0.55 s sweep,
  "Climate - BBC News" → "Climate News" as Arc. Settings ▸ Max ▸ Tidy Tab Titles, off by default (Arc's Max is
  opt-in).
- [?] Not seen: whether a drag into Pinned renames (Cra does, every pin counts), a rename whose new name isn't a
  prefix of the old (Cra crossfades in the soft edge), undo.

## Tidy Downloads (Arc 1.171, 4 Nov 2026, strings + Victor's Arc, 60 fps recordings)

Arc Max's renameDownloads: a finished download is renamed on disk and a card above the download bin says so.
- [O static] beginRename(browserContextID:downloadID:defaultFilename:sourceUrl:webContentsTitle:referrerTitle:) sends
  the file name, the source tab's title and domain with a prompt ("Rewrite its filename to be helpful, concise and
  readable. 2-4 words." plus rules and nine examples) and reads JSON `newName`; it refuses an empty name or one
  starting with ".". The card is SidebarBanner's ("Download renamed to:", "Revert to original name"); the toasts
  "Download renamed!" / "Download name reverted!" are DownloadRenamedToastContentView in Arc's toast.
- [O] Live, three GitHub zips from their repo pages: Hello-World-master.zip → "Hello World Repository.zip",
  Spoon-Knife-main.zip → "Spoon Knife main.zip", git-consortium-master.zip → "Git Consortium Master.zip" (renamed
  on disk). A second download from the same tab didn't start (Chrome's multiple-download block).
- [O] Card (dark space, 347 pt sidebar, AX + 2x frames): a button 331 × 74 pt at x 8 (the sidebar less 8 pt a side),
  body 65 pt with 12 pt corners plus a 9 pt tail at bottom left whose tip ends 1 pt above the bin. Fill #03061F;
  "Download renamed to:" 12 pt regular #343BD1, 13 pt in, cap top 12.5 pt down; the new name 14 pt semibold white,
  cap top 31; the old name 12 pt #343BD1, cap top 50, struck through; ↶ and ✕ grey glyphs centred 47 and 21 pt from
  the right, 17 pt down; four-point sparkles (5–10 pt) twinkling by the label, the names and the bottom left.
- [O] Timeline: the card comes ~2.6 s after the download starts (with a small zip), springing from the tail's tip:
  0.55× → 1.0 in 0.18 s, 1.05× at 0.29 s, settled by ~0.55 s, fading in over ~0.1 s; the strike draws left to right
  0.5 s in, over ~0.15 s. It leaves 7.96 s after it came, shrinking back to the tip and fading in ~0.12 s.
  ↶ renamed the file back at once (git-consortium-master.zip). Not captured: the reverted toast (Cra shows
  "Download name reverted!" in its one toast), the card in a light space (Cra: white, from Arc's Max picture), and
  whether hovering holds it.
- Cra: TidyDownloads (CraCore: prompt with Cra's own examples, the name's checks, a free name), TidyDownloadsService
  (FoundationModels, renames the file, DownloadHistory.move, revert), DownloadRenameCard (SidebarView, over the bin).
  Settings ▸ Max ▸ Tidy Downloads, off by default. Deviations Victor asked for (5 Nov 2026): the body is 71 pt
  (the old name's baseline as far from the bottom as the label's cap top from the top), and the card stays while the
  pointer is on it, then for what was left of its 8 s but at least 3 s. On a dark space the label and the old name are #929BFF, not
  Arc's #343BD1, which reads at 2.6:1 on the card (PR #197, Quinn Battersby; Victor, 5 Nov 2026).

## 5-Second Previews (Arc 1.171, 10 Nov 2026, Arc's binary + Victor's Arc: Hacker News, Google, example.com; 2x, 60 fps)

Arc Max's 5-Second Previews are hover cards inside Arc: the HoverCards module (HoverCardsController,
HoverCardWindow, HoverCardViewModel), pref `hoverCardsEnabled` (1 in Victor's Arc), remote flags
`hoverCardsLLMDelayInterval` and `hoverCardsShareEnabled`. Arc's server still answered.
- [B] Settings text: "Instant summaries appear when you hover over links on [certain websites.](…) Or hold Shift
  while hovering to preview any link."
- [B] Sites (`HoverCardsSupportedDomain`): google.com, x.com / twitter.com, news.ycombinator.com, each with its links:
  `.title .titleline > a` (HN story titles); `[data-testid=tweetText] a[role=link][target=_blank]`,
  `[data-testid='card.wrapper'] a[role=link]`, `a[role=link][rel='nofollow noreferrer'][target=_blank]` (X);
  `g-section-with-header a [role=heading]`, and `#search a`, `#tvcap a`, `#topstuff a`, `#botstuff a` (Google).
- [O] Which hovers: an HN story title and a Google organic result open a card; HN's "comments" link and a Google
  side-panel link don't; a link on example.com doesn't. Shift must be held as the pointer reaches the link
  (pressing it while on a link does nothing). With Shift, example.com's iana.org link got the answer card, and HN's
  "comments" link (same site) got the small card: the page's title in bold and its address without the scheme.
- [B] Prompt (HoverCardViewModel.loadSummary): "As a concise and helpful summarizer, create a glanceable "answer card"
  containing the most important information from the webpage. Capture the tone, perspective and POV of the writer."
  JSON `Response {blocked, quickSummary? (3-8 words), details: Detail[] (2-4)}`, `Detail {label ("Price:", "Story:", …),
  icon (an SF Symbol name), info (5-10 words)}`, the page between `<webpage>` tags, the user's Google search as
  `userQuestion`, "Write responses … in <language>". `blocked` shows "No preview available".
- [O] Timing: a loading card 0.97–1.2 s after the pointer comes to rest (300 × 52 pt, two grey bars 7 pt thick and
  15 pt apart); it grows down from its top edge from about a tenth of its height in 0.25 s, opaque from its second or
  third frame. The answer streams in (rows fade in as they come, the card grows down) over the next 1–3 s. Leaving the
  link closes it at once unless the pointer is on the card: it squashes toward its top edge to about a third, still
  nearly opaque, and fades at the end, in 0.14 s. With no room under the link it hangs above it.
- [O] Card: 300 pt wide, 12 pt corners. The page's picture (og:image) fills a 100 pt banner; a page without one gets no
  banner. The quick summary in bold 13 pt white, 15 pt margins; a row per detail: the model's SF Symbol in white at
  about 40 %, the text at 39 pt, bold label + regular info, 13 pt on 18.5 pt lines, 6 pt between rows. A 32 pt grey
  share button with a faint rim, its centre 24 pt from the right and 25 pt from the bottom. The fill is the space's dark
  tooltip tone at about 90 % (#322c15 over Hacker News's page in a beige space; TooltipTones gives #302913). It hangs
  6 pt under the link, 7 pt left of the link's start. The small card: 300 × 86 pt, title on 16 pt lines, 10 pt above
  the address.
- [O] Share button: a dark menu at the click, Copy as Text (doc.on.doc), Copy as Image (photo.on.rectangle),
  Share ▸ (the share services). Copy as Text puts plain text and flat RTFD on the pasteboard: the quick summary, a line
  per detail led by an emoji for its symbol (trophy 🏆, video 📹, pencil ✏️, paperplane ✈️), "AI Summary by Arc Browser",
  the link. Copy as Image is a 3x TIFF of the card in light: 304 pt wide, the picture at its own aspect inset 2 pt with
  8 pt corners, #191B1F text, #BBBBBC symbols, a dashed #CFD0FB line (4 pt on, 6 off, a 3 pt gap first) and a 50 pt
  #F6F6FF footer with the favicon and host left and "Arc Browser" bold right, both #9A9AB3.
- Cra (LinkSummaryPolicy, LinkSummaryPrompt, LinkSummaryCardLayout, LinkSummaryShare in CraCore; LinkSummaryService,
  LinkSummaryPreview, LinkSummaryShareImage): all of the above, on the Mac's Apple Intelligence model with Arc's
  prompt and schema (streamed). The page script checks Arc's selectors on the hovered link. Chromium fetches the page in
  the tab's profile only once a card opens, never for hosts on the Mac or the local network, upgraded to https with
  Always use secure connections, never in incognito spaces. Differences that stay: "Cra" in place of Arc's name in
  the copies; the emoji table is Cra's (Arc's isn't readable; it matches the four Arc produced); the model writes
  its own answers. Settings ▸ Max ▸ 5-Second Previews, off by default like Arc Max.

## Little Arc over a full-screen app (Arc 1.171, 5 Nov 2026, issue #186, Victor's Arc + a test full-screen app)

- [O] With another app full screen on its own Space, `open -a Arc https://example.com/…` (a link from another app)
  opened Little Arc on that full-screen Space (CGSCopySpacesForWindows: the full-screen Space, type 4), and the
  active Space stayed there. Cra 0.1.30 switched to the desktop Space (type 0) and opened the Little Window there.
- [O AX] Little Arc's AX subrole is `AXSystemDialog` at window level 0, with no window buttons among its AX
  children (an `AXCloseButton` attribute is still there). In AppKit only a titled `NSPanel` with
  `.nonactivatingPanel` reports that subrole (NSWindow: AXStandardWindow; NSPanel: AXDialog; utility panel:
  AXFloatingWindow; borderless: AXUnknown).
- [O, stand-in app] Why it matters: an ordinary window can't join another app's full-screen Space. With `.fullScreenAuxiliary`,
  `.moveToActiveSpace`, `.canJoinAllApplications` (macOS 13) or no activation at all, a stand-in app's new window
  still landed on the desktop. A titled non-activating `NSPanel` with `.fullScreenAuxiliary` lands on the full-screen
  Space, and `NSApp.activate` afterwards doesn't switch Spaces. With `.fullScreenPrimary` added it still enters
  its own full screen (page video).
- [O, Cra test copy] Child windows: a child ordered in before its parent is on screen, or shown by its owner before it was
  attached (Chromium's page window), stays on the desktop Space. Making it key then switches Spaces. Ordering it
  out and adding it again as a child, after the parent is on screen, puts it on the parent's Space.
- [O, Cra scenario little-window-fullscreen, 9 Nov 2026, #277] With `.fullScreenPrimary`, a Little Window shown while
  Cra's own browser window is full screen got a full-screen Space of its own (`styleMask` .fullScreen, the browser
  window off the active Space): a black screen with the card in the middle and no traffic lights. With
  `.fullScreenAuxiliary` only, it joins the browser window's Space. The page's own full screen adds primary while it
  lasts. Leaving that, macOS puts the Little Window on the desktop Space, not back over the full-screen browser
  window (as before #277). Bringing the browser window's Space back works, but the panel stays tied to the desktop
  Space even when ordered in with `.moveToActiveSpace`, and making it key switches back to the desktop.

## Little Arc's ⌥⌘N from any app, Capture scrolling, and clicks on a Peek's bar (Arc 1.171, 5 Nov 2026, issue #195)

- [O strings] Arc registers Little Arc's shortcut as a system-wide hot key: `GlobalHotkeyListenerClient.registerLittleBrowserShortcut`,
  a Carbon `RegisterEventHotKey` (`EventHotKeyID`, "Failed to register hotkey."), behind the setting
  `globalLittleBrowserHotkeyEnabled` ("Open Little Arc when I press ⌥⌘N", `onToggleGlobalLittleBrowserHotkey`). It is on by
  default (not in Victor's defaults; Arc's help and guides say ⌥⌘N works from any app). Cra: GlobalHotkey (Carbon, no
  Accessibility permission) registers New Little Window's binding while Settings ▸ Tabs ▸ Links "Open a Little Window when I
  press ⌥⌘N in any app" is on (GlobalShortcut in CraCore: only chords with ⌘, ⌃ or ⌥). A background test copy registers none.
  Checked in a test copy: ⌥⌘N with VS Code in front opened an empty Little Window with its command bar.
- [reporter] Arc's Capture lets the page scroll under it. Cra's draws over a picture of the page, so while choosing it now
  sends the wheel to the page (`Input.dispatchMouseEvent` mouseWheel, points to CSS pixels by the page's devicePixelRatio,
  40 px per wheel line) and takes the picture again as it moves (one at a time, and once more 0.25 s after the last event for
  smooth scrolling and momentum). Checked: 25 HID wheel steps scrolled a long page 1000 px with the mode on, the grey picture
  following. WebKit pages don't scroll under it (no Input domain there).
- [O, Cra test copy] Why a Peek's Back, Forward and Refresh (and Little Window's strip) did nothing: the page is a Chromium child
  window of the Little Window. With it key, a HID press on the bar reached the button but the release never reached the app (no
  local monitor saw it), and the buttons act on the release. The main window avoids this for its own children by making the
  window under a press key first (installChildClickMonitor), but a Peek's page is a grandchild of the browser window, and a
  Little Window has no such monitor. LittleWindow.sendEvent now does the same for its children. A press while the browser
  window itself was key always worked (its monitor made the Peek key), which is why it looked intermittent.

## Theme editor hover, tab-on-tab drops, Download location (Arc 1.171, static, 5 Nov 2026, #189–#191)
Read from the arm64 slice's Swift field metadata (`__swift5_fieldmd`, case and field names only; no numbers).
- [O metadata] SpaceStyleEditor module: `ColorPillButtonStyle { colorSet, _isHovered, addComplimentary }` (the preset
  swatches are a ButtonStyle with a hover state), `SpaceStyleButtonStyle { _isHovered, _isEnabled, hoverColor,
  hoverStyleEnabled }` (paging arrows, `EditColorButtonsView` − / +, `LightDarkToggleView`, each with
  `shouldEnableButtonHover`), `PadWheel { _isDraggingKnob, _isKnobHovered, _knobPositionAtDragBegin }`,
  `SpaceStyleColorPadView { _isPadButtonsHovered, _isDraggingKnob, _isKnobHovered }`.
  [?] Not measured: the hover/press scales and the hover colour. Cra (#189): swatches and knobs scale 1.08 hovered,
  0.92 pressed (ease-out 0.12 / 0.10 s, the reporter's estimates); arrows, − / +, Auto / Light / Dark get +0.3 white
  on hover; pointing hand on the arrows, open hand over a knob, closed hand while dragging one; none with Reduce Motion.
- [O metadata] Sidebar drops: `SidebarDropTarget = tabList(…) | appTray`, `SidebarDropTargetRegion = left | right`,
  `SidebarDropOperation = move | copy`, the window action `draggedToCombineSplitCompatibleItems(…)`. No drop makes a
  folder: `createFolderFromItems` / `createFolderFromSelection` are the menus' "New Folder with N Items". Cra (#191):
  a tab dropped on the middle of any tab row, pinned or Today, offers the split; Cra's own "New Folder" drop on
  pinned rows is gone.
- [O] Tab-on-tab drops, live (Arc 1.172, offline copy, 7 Nov 2026, discussion #180): the split takes the TARGET's
  place and both tabs move into it, no copies. A Today tab dropped on the left of pinned "pina" made a pinned split
  "todaya | pina" in pina's slot (minus button, gone from Today); pinned "pinb" dropped on the right of Today
  "todayb" made a Today split "todayb | pinb" in todayb's slot (gone from Pinned). The reporter's capture shows
  pinned on pinned the same way. Arc opens the tab a drag picks up, so the split ends up open with the dropped
  tab's pane focused (ring and full toolbar on it). Cra (#180): `SidebarStore.combineIntoSplit` moves the dropped
  tab beside the target (pinning or unpinning it like any drop there), then `createSplit(inPlace:)`; the list
  selects the dropped tab. Other ways into a split (⌥Return, a drop on the page, Add Split View) keep the Today
  copy of a pinned tab observed on 24 Oct.
- [O strings/metadata] Settings ▸ Profiles "Download location" is per profile: `DownloadLocationView { store,
  _selectedTag, _panelOpen }` with tags `arc.folder`, `arc.promptForDownload`, `arc.other` ("Button to confirm
  selection of directory for file downloads"). [?] The menu's own labels aren't in the strings. Cra (#190):
  AppSettings.downloadLocations per profile (folder or ask), a Downloads card under Profiles with the folder,
  "Ask Where to Save Each File" and "Other…"; save panels queue one at a time as sheets on Cra's window.

## Page context menus (Arc 1.172, 6 Nov 2026, Victor's Arc, Little Arc at 2x, AX menu dumps)

- [O] Arc shows Chromium's own Mac menu (MenuControllerCocoa): extension items carry the extension's icon (one
  item: its own title; several: a submenu named after the extension), and AppKit adds Look Up, Speech, Writing
  Tools, Services and AutoFill as it does for Chrome. System items are British ("Summarise"): Arc's bundle has
  en-GB.lproj and Victor's macOS is en-DK. Chromium items are Chrome's, with these changes:
- [O] Page: Back, Forward, Reload | Save As…, Print…, Cast…, Translate to <language> | extensions | View Page
  Source, Inspect. No "Create QR code for this page", no separate Inspect Element.
- [O] Link: Open Link in New Tab, Open Link in New Window, Open Link in Little Arc, Open Link in Incognito Window |
  Save Link As…, Copy Link Address | Copy, Copy link to highlight, Search Google for "…", Print… (the link text is
  selected) | extensions | Inspect.
- [O] Arc 1.172 on 9 Nov 2026 (#276, Victor's Arc, HID right-click on a page that is one link, AX press, active tab
  read over AppleScript): Open Link in New Tab, Open Link in New Window, Open Link in Split View, Open Link in Little
  Arc, Open Link in Incognito Window. "Open Link in New Tab" left the page's tab active and opened the link's tab
  behind it. A Russian UI (#276's screenshots) shows Chromium's Russian for New Tab, New Window, Incognito and the
  image search («Найти картинку (Google)»), English for Split View, Little Arc and Capture Image….
- [O] Selected text: Look up '…' | Search Google for "…", Copy, Copy link to highlight, Print… (search first).
- [O] Image: Open Image in New Tab, Save Image As…, Capture Image…, Copy Image, Copy Image Address, Search Google
  for Image. Video: Loop, Show all controls | Open Video in New Tab, Save Video Frame As…, Save Video As…, Copy
  Video Frame, Copy Video Address, Picture-in-Picture, Cast… (no frame search). Text field: Emoji and symbols |
  Select password | Undo, Redo | Cut, Copy, Paste, Paste and Match Style, Select All | Language Settings, Writing
  direction ▸.
- [O] Capture Image… greys the page at once, and the image (its size on the page) moves to the middle in the 4 pt
  #161C2F ring with no clearance, the capture menu 10 pt right of the ring, top level with it; its own place stays
  grey. On a 1688 × 963 pt page a 160 × 100 pt image's ring ran 623.5…791.5 pt, the 273 pt menu 801.5…1074.5.
- Cra: Chromium 156 shows the same menu once cef-patches/context-menu-embedded-view.patch lets it show in Cra's
  window. CraCEF's MakeArcMenu drops the QR code and video-frame search items, joins Translate to Save As…'s group,
  puts Search first for a selection, turns Lens's "Search Image with Google" into "Search Google for Image", adds
  Open Link in Little Window and Capture Image… (ContentCapture.liftedLayout), and opens New Window / Incognito /
  Inspect in Cra's own windows and DevTools. Items Chromium has words for read in Chromium's language, as Arc's do
  (#276, a Russian UI: «Открыть ссылку в новой вкладке», «Найти картинку (Google)»): New Tab is Chromium's label and
  the image search is Chromium's "&Search $1 for Image" filled with the engine Lens's label names (PageMenuLabels).
  Little Window, Split View and Capture Image… stay English, as Arc's Little Arc, Split View and Capture Image… do.
  One "Open Link in New Tab", behind the page as in Arc; Settings ▸ Tabs ▸ "“Open Link in New Tab” switches to the
  new tab" (openLinksInForeground, off) makes it switch (#276; until then Cra switched and had "Open Link in
  Background Tab" under it, #183). Open Link in Split View (#257) sits under New Window, as Arc's does; the link
  opens as a pane after the clicked page's (SidebarStore.openLinkInSplit), "Cannot Add New Pane" at four. Not in
  Little Windows or Peeks.

## Blank Window and dragging a tab out (Arc 1.172, 6 Nov 2026, #219 #220, offline Arc on a fake home, AX + 2x window captures)

- [O static] Window styles in StorableWindows.json: `standard { sidebarContext: global | standalone }`, `little`, and the
  kinds `standard | global | incognito | littleArc | blank`. A Blank Window is `standard` with a `standalone` sidebar:
  StorableSidebar.json keeps `{standalone: <window id>}` beside `global`, holding one space of its own (Default
  profile, `customInfo` empty, no pinned container, no top apps). Strings: `newBlankWindow`, `onCreateNewBlankWindow`,
  "Creates a new blank window.", "Title for Explore tabs in a standalone-sidebar window."; AX id
  `standaloneBrowserWindow-<id>`.
- [O] File ▸ Blank Window ⌃⌘N (AX mods 4), between New Window and New Incognito Window. It opens cascaded from the
  window in use with the command bar up. Sidebar: "This Window" (13 pt semibold, glyphs 16.5 pt in, cap top 51.5 pt
  from the window's top with the toolbar on), then New Tab (text 20 pt in, top 90 pt): no favorites or empty card, no
  pinned section, no line, no space icons; the Library button and + stay, and a click on + does nothing (no menu,
  no editor, no window). Colours follow macOS (window captures, inactive; light forced with Arc's
  NSRequiresAquaSystemAppearance): dark, sidebar #313246 → #363247 and the empty page area #4F4B5D → #584A5D;
  light, sidebar #E3E3F4 → #E9E7F1 and page area #F8F7FA → #FCF9F9.
- [O] With the pointer over its sidebar the header shows "Move to…" (grey #7A7A86, glyphs 153.5–202.5 pt of a 228 pt
  sidebar) in place of the space's •••. It is the Today section header's accessory (`moveToMainWindow`, tooltip "Move
  to main window"). A click pops a menu up at the pointer listing the spaces as icon + name ("🧑‍💻 Victor"); while
  it's open the button sits on a pill, white ~10 % over the sidebar (#474757 on #333247), 142.5–215 × 43–70.5 pt.
  Picking a space moved the window's tab to the top of that space's Today, opened it in the main window (which came
  forward) and closed the Blank Window.
- [O] Closing a Blank Window drops its standalone container and its tabs: nothing went to StorableArchive.json.
- [O] A sidebar tab dragged out and let go over another app (real HID drags, slow steps; a fast cliclick drag reads as
  a click, a press on a non-key window drags the window): the tab leaves the global sidebar and opens alone in a new
  Blank Window the size of the window it came from; that window then showed no tab (the drag had selected it). The
  window centres on where the pointer let go: 926 × 500 dropped at (1100, 700) and (500, 820) from the top left opened
  at (637, 450) and (37, 570). Near an edge it stays inside: dropped at (350, 300), a 1000 × 760 window sat at
  (20, 53), 20 pt inside the visible frame on both sides. Drags that read as clicks: the press selected an unloaded
  tab; select it first, then drag (scratch tool: CGEvent drag with deltas at 60 Hz).
- [O] A tab dropped on a Blank Window's sidebar moved there out of the global sidebar.
- [Reported, #288, 9 Nov 2026, video] A tab dragged out of a space on another profile opens in a window that stays
  on that profile: the page stays signed in. Cra's tear-off Blank Window takes the tab's profile
  (SidebarStore.moveToBlankWindow); a ⌃⌘N Blank Window stays on Default.
- Cra: BlankWindow (Space.standaloneWindowID, saved in sidebar.json outside spaceOrder), SidebarStore.addBlankWindow /
  isStandalone, TabTearOff (decision + frame), SpaceListView.dragEnded, AppDelegate.tearOffTab and moveBlankWindow
  ("Move to…", `cra://debug?blankMoveTo=<n>`), BlankWindow.theme (Auto).

## Confirmation dialogs (Arc 1.172.1, 7 Nov 2026, PR #224, offline Arc on a fake home, 2x window captures)
- [O static] Arc has two paths: `AlertClient.runModal` (NSAlert) and its own `Dialogs` module (`DialogView`,
  `DialogButton`, `SuppressionCheckbox`, `TextInputDialogView`, `PermissionRequestDialogView`,
  `NSWindow+DialogSheet.swift` → `Dialogs.SheetWindow`, "Label for the icon to press enter/escape").
- [O] Quit Arc? (shouldWarnBeforeQuitting), Delete your “<name>” Space? and Delete your <name> Live Folder?
  are all the Dialogs card, presented as a real sheet on the browser window: 450 pt wide, centred, no AX
  window of its own, the window dimmed, and macOS 26's sheet animation (fade in while dropping a few points).
  The 1 pt light edge is the sheet's own (20 % white over the card), not a stroke. Card #161C2F, 16 pt
  continuous corners.
- [O] Quit: the app icon 50.5 pt across from 43.5 pt in; "Quit Arc?" caps 120 pt down; buttons 37 pt tall
  (+1.5 pt lip) from 183.5 pt: "Quit, and don’t ask again" at the left edge (27.5 pt in), Cancel `ESC` and
  Quit `↩` at the right, ending 26.5 pt from the card's edge, 7.5 pt apart; card 248 pt tall.
- [O] Delete Space / Delete Live Folder: Arc's logo mark instead of the app icon, title caps at 120 pt, the
  message's at 157 pt, buttons from 208.5 pt; Cancel `ESC` and a red Delete / Delete Folder `↩` (fill
  #E2492C, no lighter rim, lip #41232A, key badge #E55B41 edged #E86D56). Live Folder text: "You can restore
  this folder at any time by right-clicking the sidebar."
- [O] Colours: secondary #302F60 edged #6362A9, its ESC badge #4E4C77; Quit #3339F1. Hover: 10 % white over a
  secondary button, badge included (#302F60 → #454470), 10 % black over the default one (#3339F1 → #2D33D9).
- Cra (#224, STRENCH0): `AppDialog` + `DialogPanel` (a real sheet via beginSheet) replace NSAlert and the
  borderless DialogOverlayWindow; checked against these captures on the same display, within ~1 pt and a few
  levels of colour. Arc's quit capture was taken with its command bar open; that doesn't change the sheet.

## A tab dropped on a folder (Arc 1.172.1, 9 Nov 2026, #266, offline Arc on a fake home, real HID drag, AX + saved sidebar)
- [O] Setup: one space, a closed pinned folder holding Alpha, Bravo, Charlie, Today tabs Xray and Delta, none open. A real
  drag (cliclick, 10 steps) took Xray onto the middle of the folder's row and held it there 2.5 s before letting go.
- [O] Under the drag the folder row only highlights (a darker band across it, 60 fps-sampled recording); it never opens,
  however long the tab hovers. AX read 2.3 s into the hover: the folder still closed, no child rows.
- [O] Picking the tab up opened it (window title Xray mid-drag). After the drop the folder stayed closed and showed
  only Xray under it (the open tab's peek); StorableSidebar.json saved the folder's children as Xray, Alpha, Bravo,
  Charlie: the dropped tab goes in FIRST.
- Cra (#266): `SidebarStore.dropIntoFolder` inserts at index 0 in the picks' order, leaves the folder's open state
  alone and peeks an open tab it took; the 0.6 s spring-loaded opening in `SpaceListView.dragUpdated` is gone.
  Not changed: Cra still doesn't open the tab a drag picks up (only a split drop does).

### Back closes a link's tab, and history outlasts a relaunch (Arc 1.172.1, 9 Nov 2026, GitHub #273)
- [O data] StorableSidebar.json: a tab a link opened keeps `referrerID` (the tab it came from, always equal to its
  `activeTabBeforeCreationID`); 194 of Victor's tabs have one, pinned tabs too (Arc doesn't clear it on Pin).
- [O strings] The toolbar's state has `_canNavigateBack` beside `_canGoBack`, and the tab close reasons include
  `navigateBackToReferrer` (with `clearUnpinnedTabs`, `externalProtocolAutoClose`).
- [O data] Page history: StorableSessionRestorationData.json maps each sidebar item (`itemId` + window/profile)
  to a Chromium session tab id; Chromium's own session files (User Data/Default/Sessions/Session_*, Tabs_*) hold
  that tab's navigations with their page state, so Back and the scroll position survive a relaunch.
- [O live] Offline Arc (fake home, sidebar with referrerIDs, AX + real row clicks): a Today tab with a referrer
  and no history shows Go back enabled; pressing it closes the tab (its row goes) and selects the referrer. A
  pinned tab with a referrer and no history keeps Go back disabled, and pressing it does nothing. The mouse's back
  button (a synthetic button-3 event over the page) did nothing on a referrer tab with no history, Go back
  enabled: it stays the page's own history.
- Cra: `BackToReferrer` (CraCore) decides history / close / nothing (pinned tabs and split panes: history only);
  `TabData.referrerID` is saved, set by `BrowserManager.openLinkTab` and popup tabs. `PageHistory` (CraCore) +
  `PageHistoryStore` keep each tab's list in PageHistory/<tab id>.json: Chromium's serialized navigations from
  `Cra.getHistory` (freezing-vote.patch, the current entry ±6 like Chrome's session service, page state
  included), put back with `Cra.restoreHistory` (NavigationController::Restore) into a page made without an
  address; WebKit pages save WKWebView's interactionState. Saved a second after a load, when the tab is hidden
  and at quit. `MainWindowController.goBack` takes ⌘[, the toolbars and the menu; the mouse button is
  Chromium's. Readouts `cra://debug?back=<label>`, `cra://debug?scroll=<label>`.
- [O disasm] The two-finger swipe (Arc 1.172, 12 Nov 2026, GitHub #370, static only: a real swipe can't be
  synthesised). Arc uses Chromium's HistorySwiper (ArcCore has it and `ChromeRenderWidgetHostViewMacDelegate`),
  but its `canNavigateInDirection:onWindow:` (arm64 0x43326a8) and `navigateInDirection:onWindow:` (0x4332784)
  first ask the page's NavigationController and, when it can't move, call `arc::WebContentsUIDelegate::
  CanExternallyNavigate` / `WillExternallyNavigate` (0x44b38a8 / 0x44b3d08, through `delegate_wrapper.h`
  InvokeSync / InvokeAsync). In Arc.app those reach `ADK.WebContentChromium webContents:canExternallyNavigate:` /
  `willExternallyNavigate:`, and `WebContentFrameAction` has `canExternallyNavigate(direction:response:)` and
  `onNavigateExternally(ArcNavigationDirection)`: the app decides a swipe the page can't take. Stock Chromium
  only asks the page (`chrome::CanGoBack`). So a swipe back on a link's tab with no history goes where Back
  goes (closing it, `navigateBackToReferrer`); the mouse button never goes through the swiper.
- Cra (#370): `ChromiumHistorySwipe` replaces the same two methods; when Chromium's answer is no for Back it
  asks `BackToReferrer.swipeBack` for the tab whose page view it is, and at the end closes the tab to its
  referrer. Forward stays Chromium's. Readout `cra://debug?swipeBack=<label>[&go=1]` calls the page's real
  delegate (scenario `swipe-back`).

## Sidebar width and the narrow header (Arc 1.17x, 9 Nov 2026, GitHub #287)
- [O disasm] `WindowLayoutController.handleSidebarResizePanGestureRecognizer:` (arm64, 0x100221030): the new
  width is `round(start + translation)`; under 82 pt the sidebar hides; otherwise it's clamped to 164…500 pt.
  Snap target = insets 8 + 8 + 4 × 47 (tile) + 3 × 8 (gap) = 228 pt (constants at 0x1037e8500…), within 14 pt
  and under 50 pt/s of pointer speed. `SidebarResizeState` holds `canSnapToDefaultWidth`, `breakpointIndex`,
  `timeOfSnap`; a haptic is played on the snap.
- [O live] Offline Arc, one continuous slow press (2 pt steps, width read over AX each step): from 260 down,
  free to 242, 228 from 240 to 216, 214 at 214; held at 164 below that; hidden from 80 down (AX rows gone), and
  back at 164 from 85 up while still held; released at 149 → 164. Slowly up from 200 (1 pt steps): free to 228,
  228 from 229 to 241, 242 at 242 (no early pull from below). A quick drag to 220 stays 220. Max 500.
- [O live] Dragged shut, the sidebar keeps the width the drag started from (hidden at 200 → ⌘S → 200; the View
  menu reads Show Sidebar). The first time only, a tip toast at the top right: "You can use [⌘S] to easily show
  and hide your Sidebar!" (defaults `hasHiddenSidebarWithGesture`; a second drag-hide shows nothing), up ~4–10 s.
- [O live AX] Toolbar hidden (`topBarURLEnabled` NO), each width opened on its own: 213 and 212 regular (toggle at
  73 / 72, ← at 107 / 106), 211, 210, 209 narrow (← → ••• at 121/149/177 for 211). Regular: toggle at 77, ← → ↻
  32 pt boxes 2 pt apart ending 6 pt from the edge, the toggle stepping left to stay 2 pt off ←. Narrow
  (`SidebarHeaderWidthLayout.narrow`): no toggle; ← → ••• 28 pt boxes touching, ending 6 pt from the edge.
- [O live AX] Toolbar shown: the header has the toggle alone, 32 pt at 214, 28 pt at 190 and 164 (same x). On a
  Developer Mode page (localhost via AppleScript `make new tab`) it carries toggle + ← → ↻ (← at width − 107,
  toggle 71 at 212) and goes narrow below 212 like the toolbar-hidden header, ← → ••• included.
- [O 1x captures] ••• opens a popover (••• turns ✕): 200 × 96 pt body, radius ~12, a 12 × 6 pt arrow whose tip is
  10 pt under the button, centred on it; 8 pt padding, rows 40 pt: Reload ⌘R (dimmed with no tab), Toggle Sidebar
  ⌘S; icon centred 27.5 pt in, 13 pt semibold title at 50.5 pt, shortcut "⌘ R" ending 21 pt from the right. It
  opens with the first enabled row highlighted; the highlight follows the pointer over enabled rows and clears over
  a disabled row, the padding or outside; ↓/↑/Esc did nothing; a click outside or on ✕ closes it.
- [O] Tones: fill = black + 15 % shadedDark, hovered row = fill + 41 % shadedDark + 13 % white. Yellow "Lab"
  (0.437, 0.336, −0.080): (17, 13, 0) and (81, 70, 26); blue JYSK (0.122, 0.166, 1.026): (5, 6, 39) and
  (47, 51, 145), predicted (5, 6, 39) and (47, 52, 147). Disabled text (121, 120, 129); a shortcut ≈ white 30 %.
- [O] Cra's traffic lights sit ~1 pt wider apart than Arc's (centres 20/44/68 vs 20/43/66 at 1x) and its toggle
  2 pt right (glyph 86–103 vs 84–102 at 220 pt); not part of #287.
- Cra (#287): `SidebarWidth` (164…500, drag + Arc import), `SidebarResize` (edge under the pointer, snap, hide and
  return, start width kept), `SidebarHeaderLayout` (switch below 212, boxes, toggle shift incl. Developer Mode),
  `SidebarMoreMenu` + `SidebarMorePanel` (popover), the tip through `ShinyToast` with a key cap
  (`hasHiddenSidebarWithGesture` in Cra's defaults). Cra traced the same widths live (test copy, 9 Nov).

## Sidebar parity: favorites, tones, the hidden sidebar (Arc 1.172.1, 9 Nov 2026, GitHub #293)

Offline Arc on a fake home made from Victor's own Storable*.json (two spaces: Victor, light vibrant yellow;
JYSK, dark), network denied, `topBarURLEnabled` NO for the run (URL field in the sidebar). The Cra test copy
imported the same files (`cra://import?source=arc`). Stills with `screencapture -l` at 1x (external) and 2x
(built-in); hover with HID pointer moves while Victor was away; the hidden sidebar recorded with a 120 fps
ScreenCaptureKit region recorder that also drives the pointer and logs each move on the same clock.

- [O 1x] Favorite tiles: a site's icon is 16 × 16 pt (Cra drew 20), centred with the half point dropped
  (x 28–43, y 105–120 in a 56 × 47 tile at x 8, y 90). YouTube and Gmail use Arc's own tray art
  (`YouTubeAppTrayIcon`, `GmailAppTrayIcon`, 42 pt images), 20 × 14 and 14 × 12 visible; Cra keeps favicons.
- [O 1x/2x] At rest the URL pill and the tiles have one fill: black 0.045 on the light space (193/184/146 and
  196/182/146 over 206/192/153), white 0.095 on the dark one (58/58/75 over 37/37/55). Hovered, both take one
  fill: black 0.09 (183/175/141, 185/175/141 over 202/192/155) and white 0.145 (69/69/85). Cra's pill went to
  `selectedFill` (white 0.74 on light themes, 243/240/231) and its dark tiles to white 0.15.
- [O 1x] Space header title: black 0.46 over a light theme (113/102/83 over 208/190/154), white 0.45 over a dark
  one (135/136/146 over 37/37/55); rows are the theme's full ink. Cra had black 0.5 (99/94/76).
- [O 120 fps] Hidden sidebar, reveal: the sidebar starts ~145 ms after the pointer reaches the edge gliding in and
  ~150 ms after it jumps there without moving; an edge brushed for ~80 ms (glide in, 60 ms, glide out) shows
  nothing. Arc reacts to a hide in ~35 ms, so its wait is ~110 ms. Cra revealed on its first 30 Hz sample
  (54–90 ms, first frame already 40–55 % out), so passing the edge flashed it. Cra: `revealDwell` 0.1 s, counted by both the 30 Hz poll and the
  shell's own mouse-moved path (that one called `show()` at once, so the edge still flashed with the poll's wait in
  place). Arriving in the strip stages the sidebar in its panel out of sight (~90 ms of main-thread work, done
  during the wait; it used to delay the first frame), and the spring starts 25 ms late so its first frames reach
  the screen (they appeared 25–55 % out). Cra measured after (120 fps, built-in display): first frame ~165–185 ms
  after the pointer arrives, at 16 %, then Arc's curve a frame ahead; the 86 ms brush shows nothing.
- [O 120 fps] Reveal motion (right edge per frame, jump-in): 2, 64, 99, 132, 162, 188, 209, 227, 241, ·, 260, 265,
  269, 271, 273 (peak ~117 ms), back to 269 by ~230 ms. Fitted spring (mass 1): stiffness 759, damping 46.3,
  initial velocity 23.3 (ζ 0.84), every frame within 9 pt.
- [O 120 fps] Hide motion: 245, 215, 181, 147, 115, 87, ·, 42, 26, 14, 1, 0 and 236, 204, 170, 136, ·, 78, 55, 37,
  22, 0. Fitted bezier (0.14, 0, 0.53, 1) over 0.102 s, within 3 pt. Cra's was the ⌘S hide's 0.085 s on
  (0.15, 0.7, 0.3, 1), its first frame already ~45 % gone.
- [O 120 fps] Leave boundary: a slow pointer (3.5 pt per 28 ms) sent the 264 pt sidebar away at x 344–348
  (window-local); a fast one between 349 and 407. So ~81 pt past the sidebar's width; Cra let go 32 pt past it.
  Cra: `leaveSlack` 73 (+ the 8 pt margin).
- [O 2x] The floating sidebar's edge is a soft shadow only. Cra's floating panel had a window shadow, which macOS
  draws with a hard 1 px rim round the panel's shape: the "stroke" in #293. Arc's own edge darkens ~7 % for 4–5 pt, ~1.5 % at
  6 pt and nothing from ~8 pt on every side (fit: the sidebar grown 5 pt, shadowRadius 3, opacity 0.07, no offset; a
  no-tab window, measured against the gradient 80 pt further right). Cra now draws that as a layer shadow in a
  click-through panel under the sidebar's, with the sidebar cut out of it.
- Not changed: Arc's folder names read semibold in both spaces (Cra regular); not part of #293.

### Music notes on a playing favorite (Arc 1.172.1, build 90370, 10 Nov 2026)

Reference: `strings` and Swift field metadata on the arm64 binary, `assetutil` on ARCUI's Assets.car,
and lldb's disassembler for constants, with Objective-C calls resolved through selector metadata.
Visual references: paired YouTube Music footage in dark spaces and light-theme screenshots,
10 Nov 2026; live Arc 1.172.2 against a Cra test copy at 1x and 2x, 11–12 Nov 2026 (below).

- [O static] The top-apps item state has `shouldShowMusicalAnimation`, and `AppTrayItemViewAppKit` a lazy
  `musicIconAnimationView`: an `ARCUI.ParticleNSView` (ParticlesView.swift), a `CAEmitterLayer` filled from a
  `ParticleTemplate` (cases `pulse` and `musicNotes`). The tile also removes that view from its superview and
  drops it; [I] that is what happens when the flag turns off, so the notes go at once.
- [O static] Music sites, a static array of 8 hosts beside ARCUI's `MusicalIcon`: bandcamp.com,
  music.apple.com, music.youtube.com, nts.live, pandora.com, soundcloud.com, spotify.com, tidal.com. A URL
  matches when its host is one of them, ends in "." + one of them, or has one among its dot-separated labels.
  youtube.com is not there.
- [I] The flag is "the tab plays audio and its URL is a music site" (`_isAudible` and `browserIsPlayingAudio`
  exist; where they meet the list wasn't traced). [O live, 1.172.2] A muted tab keeps its notes: more than
  10 s after muting (mini player showing the struck-through speaker) new notes still rose. So the flag
  follows Chromium's audible state, which a mute doesn't clear.
- [O static] `ParticleTemplate.musicNotes` is two cells that differ in image and birth rate: `MusicSprite1`
  (one eighth note) 1.4 a second, `MusicSprite2` (two notes under a beam) 1.0. Both: lifetime 2, lifetimeRange
  0, scale 0, scaleRange 0.2, scaleSpeed 1, alphaRange 0.15, alphaSpeed −0.5, emissionLongitude π/2,
  emissionLatitude 0, emissionRange π/3, velocity 20, velocityRange 5; no spin, no acceleration. The emitter
  layer's `beginTime` is not set, so it shows as if it had been running.
- [O static] The sprites are 6 × 6 pt template images (12 × 12 px, a 2x rendition only, gray). Each is redrawn
  in the tint with `NSImage(size:flipped:drawingHandler:)` (the sprite, then a `sourceIn` fill) and given to the
  cell as a CGImage. Tint: white 0.8 when the tile's effective appearance is dark, else black 0.6.
- [O static] On the tile: `emitterShape` circle, `emitterSize` 6 × 6, `emitterPosition` the
  particle view's centre, set on layout; the view's frame is the tile's bounds grown 30 pt on every side, then
  `CGRectOffset` by (0, −8).
- [O still] 2x still, a YouTube Music favorite in the top row (tile 50 × 47 pt, icon 16 pt): one sharp note about
  4 × 6.5 pt some 12 pt above the icon's centre, and soft, fainter ones 11–12 pt across about 24 pt above it,
  cut off 8 pt above the tile, where the URL field ends. No note over the icon. [I] So −8 is up (the tile is
  flipped): the emitter sits on the icon's top edge. And the cell's image is 12 px drawn 12 pt wide at scale 1
  (about 0.55 at 0.45 s, 1 at 1 s with alpha near 0.4), which is why a grown note is soft on a 2x display; a
  6 px image would put the large notes at 1.9 s, when they are all but faded out.
- Cra implementation: `MusicNotes` holds the host policy, particle values and placement geometry.
  `MusicNotesView` uses a `CAEmitterLayer` with two independently drawn notes on a 12 px grid.
  `FavoritesGridView` keeps the overlays above the tiles; a split emits from its first eligible playing
  pane. The pager mask allows 8 pt above the top row, following the still; empty columns keep their
  original clipping.
- Cra policy choices: require an exact music host or its subdomain and current sound playback, muted
  or not, as Arc does. Notes follow the immediate sound callback so pausing removes them before the
  speaker's 2 s recently-audible hold expires. Reduce Motion doesn't stop them (Arc's don't stop either,
  below).
- [O capture, 10 Nov] Paired dark-theme footage (12.32 s, Arc left, CraDev right) shows notes above
  each music icon, growing softer and fading under the URL field. The grids have different tile
  counts, so widths differ. Live pause/resume was checked in CraDev.
- Cra's independent artwork uses black 0.3 on light tiles, a visual fit to the paired light-theme
  screenshots rather than Arc's static tint value above. Dark notes remain white 0.8. The pixel
  harness checks both sprites on fixed backgrounds at 1x and 2x: about 179/255 on white for light
  notes, 204/255 on black for dark notes. It fails with the previous, heavier light tint.
- Validation: `scripts/test.sh` passed, including a browser-manager regression test that failed on
  the pause delay before the fix. The release build and `music-notes` scenario passed with no faults.
  The scenario plays a quiet tone from the local fixture server mapped to nts.live and reads
  `cra://debug?musicNotes=`. It covers a non-music host, an idle music favorite, playing, muting,
  unmuting, pausing, quick resuming and the emitter's offset. Paused readouts poll for one second,
  before the speaker's hold expires, to allow Chromium's asynchronous sound event to arrive.
- Live comparison, 11–12 Nov 2026. Arc 1.172.2 refuses a second instance while one runs ("Arc is
  already open. Only one instance of Arc can be opened at a time"), so the offline copy of "One space"
  no longer works beside the user's Arc. A clone with another bundle id dies in CloudKit once re-signed
  ad hoc and is killed by code signing when it isn't. Arc was therefore the user's own: a new window,
  www.nts.live's live stream (Mac output muted; the audible state doesn't depend on it), made a favorite
  with the command bar's "Favorite Tab" and removed with "Unfavorite Tab" afterwards. As the fifth favorite
  at 264 pt it sat in row 2 (three columns), so the notes rose over the tile above. Cra was a test copy
  with six favorites (two on music hosts mapped to a local tone page), row 2 playing too. Both windows were
  1280 × 800 on a CGVirtualDisplay at 1x and at 2x, recorded with ScreenCaptureKit at 30 fps, 5–6 s per
  take, light and dark spaces. Statistics per take: a per-pixel median as background, note pixels
  differing by more than 14/255.
- [O live] What matches, at 1x and 2x: the emitter on the icon's top edge, rows above drawn over (notes
  cross the tile above), the fan opening upwards, notes gone by about 44 pt above the icon's centre, the
  same rise of glyph size with height (1x medians 3, 4, 6, 11, 11, 14, 14 pt in 4 pt bands from the
  emitter; Cra 3, 5, 7, 13, 12, 14, 15 pt) and the same fade of peak ink with height (dark, 1x: Arc
  116 → 28, Cra 128 → 33 over 2–34 pt). In Arc's light space notes are faint (about 32 pt² of note
  pixels per frame against 124 pt² in its dark space), in line with Cra's 30 % black ink.
- [O live] Pause: the notes go within 0.2 s of the stream stopping and come back on resuming, as in Cra.
  Mute: they stay (above). Reduce Motion (System Settings ▸ Accessibility ▸ Motion, on for 5 s, then
  off): unchanged, 32.0 pt² of notes per frame with it on against 32.4 before and 31.8 after.
- [U] Density and spread: Cra showed about 3.7–4.2 notes per frame and a fan about 50 pt wide, Arc
  2.6–3.1 and about 36 pt. Each take holds only some 14 births (2.4 a second for 6 s) and Arc's leaned
  left in one take and right in another, so this is within sampling noise; the cell values are the
  same. A longer Arc take would settle it.

## Full screen: the page edge to edge, the sidebar over it (Arc 1.172.1, 10 Nov 2026, GitHub #315, offline Arc on a fake home)
Offline Arc, View ▸ Enter Full Screen and View ▸ Hide Sidebar over AX, the pointer moved with cliclick; screen
captures on a 1920 × 1080 display at 1x and on the built-in display at 2x. A local page asks for element full
screen on a click.
- [O] Full screen, sidebar shown: the card keeps the window's 10 pt inset and its rounding (1x: card at
  x 228–1910, y 10–1070 beside a 228 pt sidebar).
- [O] Full screen, sidebar hidden: the card fills the screen, square, with no inset and no shadow; the toolbar
  runs along the screen's top edge. A window keeps the 10 pt inset with the sidebar hidden (25 Oct, above).
- [O] With the sidebar hidden in full screen, the pointer at the left edge (1–2 pt in, moving) brings the
  floating sidebar out over the page, which doesn't move; it goes when the pointer moves away.
- [O] A page in element full screen (Cra's `contentFullscreen`): the same edge brings the floating sidebar out
  over it too.
- [O] The floating sidebar in full screen has no traffic lights: its toggle glyph is 20–38 pt into the panel, as
  in the docked full-screen sidebar. The panel sits 5 pt in, with a 1 px light rim (1x).
- [U] A sidebar shown before a page went element full screen: whether the edge brings it out then. Cra lets it.
- Cra: CraCore `CardFill.fillsWindow` (edge to edge, or full screen with the sidebar hidden) sets the card's
  inset, rounding and shadow, the page windows' corners, Peek's backdrop and the 5 pt reveal strip;
  `FloatingSidebarGeometry.mayReveal` lets the edge reveal over a full-screen page; the floating panel draws
  its stand-in lights only outside full screen. `cra://debug?windowState` reports the card's insets
  (`card=l,b,r,t rRadius fills=0|1`); `fullscreen-hidden-sidebar.scenario` checks all three states. Cra's
  panel sat 8 pt in (Arc 5) until #350 (11 Nov), now 5.

## Page translation (Arc 1.17x, 10 Nov 2026, GitHub #310, strings + offline Arc, dark mode, 1x, AX)
- [O static] Arc draws its own translate UI (Translation/TranslateFeature, TranslateBubblePopoverView) on Chromium's
  translate state: "Translation Available" ("Title for the translation affordance below the URL", plus a narrow-sidebar
  title), the toolbar's `contentToolbarTranslateButton` (`character.bubble`, `.fill` when translated, "Translation
  Options"), the prompts "Translate this page to %@?" and "Translated from %@.", Options' "Choose Another Language",
  "Never Translate This Site" and "Language Settings", and the toasts "Translated to %@", "Translated back to %@" and
  "Translation error (%@)". Never Translate This Site is Arc's own defaults key `translateNeverHosts` (bare hosts);
  Settings ▸ Advanced has "Reset Translated-site Prompts".
- [O] Toolbar: the button shows only once Chromium knows the page's language and can translate it, per tab. 32 × 24 pt
  on the nav buttons' line, right before the Site Control Center's sliders (frames 36 pt apart), ink 16 × 15 pt in the
  sliders' tint. Chromium's own bubble never shows; no popover opened by itself on a reload.
- [O] Popover: an NSPopover under the button, 262 × 128 pt with the arrow (tip on the button's centre, 10.5 pt tall),
  body 236 × 102 pt from 13 pt under the button, continuous radius ~19, Arc's dark material (grey 110 over a white
  page). A 32 pt badge (`textformat.alt`, 17 × 10) 10 pt in, 11 pt down; the question in 14 pt regular from 50 pt in,
  two lines of 17 pt, centred on the badge; two 104 × 32 pt buttons 7 pt apart, 10 pt from the edges, 14 pt semibold:
  Options flat (118 on 110, radius ~4) and Translate raised (148, hairline border, radius ~5.5). Translate closes it.
- [O] Toolbar hidden: an AXButton "Translation Available", 122 × 17 pt, under the URL text and on its left edge (text at
  6 pt from the field's top, the line at 23 pt); the tab list starts 2 pt under it.
- [?] Not observed: the URL line's pixels, hover and narrow title; the translated state and the toasts (offline Arc
  fails with a network error and shows nothing); Options' anchor; light mode.
- Cra: PageTranslation (CraCore) on the state Chromium sends as "Cra.translate" and the Cra.getTranslateState /
  translatePage / revertTranslation / neverTranslateSite methods (translate-ui.patch, freezing-vote.patch);
  ToolbarComposition's `.translate`; TranslatePopover; SidebarURLPill's line (the field 42 pt tall with it). SDK 26
  draws NSPopover as light glass, so the body is filled to Arc's material; the arrow stays the system's (full-size
  content clipped the body's edges). Chromium
  offers translation only with a Google API key (release builds' CRA_GOOGLE_API_KEY); dev builds show no button.

## Page-top window dragging (Arc 1.172.2, build 90755, 10 Nov 2026, arm64 static analysis)

- [O static] `WindowContentViewController` installs an `ARCUI.WindowContentGrabber` when
  `contentWindowDraggingEnabled` changes to true; its delegate also decides whether grabbing is allowed.
- [O static] The grabber's eligibility helper at `0x100b21f24` compares `NSCursor.current` with
  `NSCursor.arrow` using NSObject equality, then combines that result with the delegate's permission.
  Its `hitTest:` path at `0x100b21c54` and `mouseDragged:` path at `0x100b2210c` call this helper before
  `performWindowDragWithEvent:`. Text, pointing-hand and resize cursors therefore fail this check.
- [O static] Layout helper `0x100412cf4` makes the grabber's frame start at x = 0 with
  width = content width minus 14 pt (`fmov d1, #-14` at `0x100412f68`). The frame stored at
  layout offset `0xf0` is applied to `grabberView` by `setFrame:` at `0x100412988`.
  The rightmost 14 pt therefore stay outside the grabber even with an arrow cursor, leaving the
  vertical scrollbar to the page. Cra reserves the same strip through `PageTopDrag.trailingInset`.
- [I] This path distinguishes page actions by their cursor, rather than by a list of DOM element tags.
  An element that forces the ordinary arrow does not receive the same exclusion as a text or link cursor.
- Cra: `WindowContentGrabber` lets the press reach the page immediately, checks the cursor again before
  starting a system drag of the browser window, and leaves the window's native resize edge band free.
  The existing 56 pt page band is still `PageTopDrag.band`; no new live Arc measurements were made here.

- [O AppKit probe, 10 Nov 2026] On a 1000 × 700 pt titled, resizable full-size-content window,
  `_resizeDirectionForMouseLocation:` reports a corner resize 8 pt inward from both the top and right
  edges. A uniform 3 pt inset therefore misses part of the rounded corner's target.
  [Chromium's frame-view handler](https://chromium.googlesource.com/chromium/src/+/master/components/remote_cocoa/app_shim/native_widget_mac_nswindow.mm)
  checks this same AppKit method before moving the window (`-1` means no resize). Cra's
  `WindowDragRegion` now uses that check in the owner window's coordinates, with the 3 pt inset
  only as a fallback when the selector is unavailable.

- [O Cra runtime, 10 Nov 2026] The remaining page-corner drag bypassed both the page grabber
  and `CraWindow.performDrag`: `windowWillMove` arrived through AppKit's
  `NSAppInstallWindowWillDragEventMonitor`. Changing movement flags during `sendEvent` did not stop it.
  Chromium's original `BridgedContentView` excludes its bounds from server-side titlebar dragging through
  [`_opaqueRectForWindowMoveWhenInTitlebar`](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/components/remote_cocoa/app_shim/bridged_content_view.mm).
  Cra leaves that container behind when embedding the page, so `WindowContentGrabber` now preserves the exclusion.
  A native AppKit drag-region query reproduces the unwanted corner region before attachment, excludes it with
  the grabber attached, and restores it after detachment. The user confirmed the corner fix in CraDev.

- [O static, 11 Nov 2026, the same build, read again for the review of #335] `WindowContentGrabber` overrides
  only `hitTest:` and `mouseDragged:`: no `mouseDown:` or `mouseUp:`, no stored event and nothing replayed. On a
  left press over a window with content `hitTest:` returns nil, so the page gets the press at once, and the
  grabber only notes whether the press was eligible (`dragState = .beganInValidState`). On the first eligible
  drag event it calls `performWindowDragWithEvent:` with no distance threshold (Cra keeps its 3 pt slop), then a
  local monitor swallows the drags and the release. The delegate's permission is asked on the press only; on a
  drag the test is the arrow cursor alone.
- [O static] The band's far edge is 60 pt in the controller's view (`60 − y`, y the bar's bottom edge: 0 with no
  bar). Measured on 11 Nov: 60 pt into the page with no bar, 28 under the toolbar (below).
- [O Cra, real pointer events, 11 Nov 2026] On #335's build, toolbar hidden: an arrow drag in the band moved the
  window and the page saw the press; a click reached a button there; a drag over text selected it; the right
  14 pt and a press 130 pt down stayed with the page; the window's top-right corner resized. On the build
  before it, the text drag, the right strip and the corner all moved the window.
- [O Cra, real pointer events, 11 Nov 2026] On an inactive Cra the press finds a stale cursor (`NSApp.isActive` false and
  `NSCursor.current` whatever Cra set when it was last in front), so an arrow drag in the band moved the window only
  2 times in 4. Such a drag also ends with two `leftMouseUp` events 3 ms apart, and the page took the second for a
  click on what the drag started on. Cra now leaves the cursor out for a press on an inactive Cra or the press that
  brings it to the front (`PageTopDrag.cursorIsCurrent`), and keeps every release after a window drag from the page:
  7 drags in 7 moved the window, and a drag starting on a button no longer pressed it. [U] Arc's own behaviour on an
  inactive window: its grabber makes the same cursor test, not measured.
- [O live, Arc 1.172.2 and Cra side by side, real pointer, 11 Nov 2026, #363] Same 1300 × 640 window at 40,440 on the
  2x built-in display, a local page whose top 64 pt row holds a text field, a button with the arrow cursor, one with
  the pointing hand and blank space; the page logs every press, release and click by its distance from its top, the
  window's frame is read over AX after each gesture (rig in build/issue-363-rig). Drags are 60 × 30 pt over 250 ms.
  - Band: toolbar hidden (card 10 pt below the window's top), drags 57, 58 and 59 pt into the page moved the window,
    60 and 61 didn't. Toolbar shown (page 42 pt down, under the 32 pt bar), 25–27 pt moved it, 28–30 didn't. Both fit
    `60 − bar`: the band ends 60 pt below the card's top, and the grabber works under the toolbar too. The 7 Nov
    "56 pt, 58 no" was off by a few points; Cra had 56 and no band under a bar.
  - Start: the first drag event starts the window drag, however small: 1, 2 and 3 pt glides (several events) moved the
    window 0–2 pt, and the window lagged the pointer by the first event's movement (a 60 pt drag moved it 59). A
    single 5 pt drag event moved nothing. Cra waited for 3 pt and moved the window from the press.
  - Release: after a window drag the page gets the release and a click (a drag that starts on the arrow-cursor
    button clicks it). Cra swallowed the release, so a click that slipped 5 pt on the button moved the window and
    never clicked: the "lost click" of #363 on 0.1.40.
  - Same in both: clicks 1–20 pt down on any control reach the page; a drag on the text field selects text and one
    on the pointing-hand button stays with the page; the right 7 pt stay with the page, 20 pt in moves; a click in the
    10 pt margin above the card does nothing, a drag there moves the window and a double-click zooms it; a
    double-click in the band goes to the page.
  - Inactive window (a windowless app in front): Arc's page gets no event from a first click anywhere, 4, 100 or 200
    pt down; a drag in the band moves the window. That is Arc not taking the first click at all, not the grabber.
    Cra passes a first click to the page; left as is (window-wide, not the band).
- Cra (11 Nov 2026): `PageTopDrag.band(barHeight:)` = 60 − the card's bar (`WindowContentGrabber.barHeight`); the
  grabber starts the drag on the first drag event, from that event's point; the page gets the release unless the
  press brought Cra forward (the two releases above). [U] Arc's split panes and its 40 pt developer bar: the same
  `60 − y` rule read statically, not measured.

## The hidden sidebar from past the window's edge (Arc 1.172.2, 11 Nov 2026, GitHub #350, live Arc, real pointer at 120 fps)

The reporter's recording (60 fps, 2x): a pointer thrown out past the left edge of a window that stands
clear of the screen's edge, 95 pt out and then to the screen's edge 154 pt out, brings the sidebar out,
and it stays while the pointer is out there. Cra revealed only in its 14 pt strip.

Measured on Arc with the sidebar hidden (View ▸ Hide Sidebar), a 264 pt sidebar, the window at x 420,
y 120, 1100 × 800, a local page in the tab. One tool drove the pointer (HID mouse-moved events, 4 ms
steps) and read the window's frames (ScreenCaptureKit, 1x, 120 fps) on one clock; coordinates below are
points from the window's left edge (negative = outside) and from its top. Names in the binary:
`offLeftEdgeZoneRect`, `innerLeftEdgeZoneRect`, `innerTopLeftEdgeZoneRect`,
`floatingSidebarOuterLeftEdgeHoverState`, `HoverRegionTracker` (ARCUI), and a region enum with
`offLeftEdge`, `windowTrafficLightRegion`, `innerLeftEdge`, `innerTopLeftEdge`, `sidebar`.

- [O] Thrown from the page to x −100 (80 ms), at rest there: out, first frame 135–160 ms after the pointer
  stopped (nine runs). It stays out while the pointer moves beside the window (y 200 to 400).
- [O] Out with the pointer at rest at x −3, −20, −60, −150 and −250; not at −270, −290, −300, −330 or −410.
  A sidebar that is out, the pointer moving left at 150 pt/s: it starts back in with the pointer at −257
  (Arc takes ~35 ms to react, so it let go at about −252). The zone is ~256 pt wide: the sidebar's width
  less its 8 pt margin. [U] other sidebar widths.
- [O] Up and down, at x −50 and −100: out when the pointer leaves the window at y 45, 60, 740, 792; not at
  y 8, 15 or 30. Out, moving up at 50 pt/s it starts back in at y 30; moving down at 150 pt/s at y 823
  (23 pt under the window). So Arc's zone runs from ~32 pt under the window's top to ~17 pt under its
  bottom: the sidebar's height, set ~24 pt low. Cra uses the window's own height.
- [O] Only a pointer that comes out of the window counts. One that reaches the zone from above (x −100,
  y −60 to 400), from below (x −60, y 900 to 400) or from further left (a jump from −350 to −100, then
  nudged and moved on to −150) brings nothing out in 1–2 s. From x −60 on to −2 it does come out: the
  window still gets mouse-moved events 2–4 pt outside its frame, where the 5 pt strip's rule holds
  (the "2–4 pt outside" measured on 29 Oct).
- [O] The wait. A pointer that stops: ~145–160 ms after its last move (thrown to −10, −40 or −100, a jump
  with no move after it, 300 pt/s stopped at −10: 142 ms). One that keeps moving outward at 100, 200, 300,
  600 or 1500 pt/s: 218–227 ms after it crossed the edge, every time, wherever it was by then (x −22 to
  −200). Stopped at −40 after 131 ms outside: 231 ms after crossing. So the wait starts over while the
  pointer moves, but only for its first ~75 ms outside. In the strip, stopped at x 3: 147 ms.
- [O] Out 40 pt and in again to x 60 within 30 ms: nothing. Thrown to −300 or on to −410: nothing.
- [O] Above the window's top (x −100, y −60) the sidebar leaves; back beside the window it stays in.
- [O] The reveal and the hide are the curves fitted on 9 Nov (#293): right edge per frame 9, 39, 72, 107,
  139, 193, 214, 231, 244, 254, 262, 267, 270, 272, peak 274, rest 270; back in within ~0.1 s.
- [O] Nothing came out from the window's top-left corner (x 3–400, y 3–60, 0.7 s each), whatever
  `innerTopLeftEdge` and `windowTrafficLightRegion` are for.
- [O] Out with the pointer at rest at x −100, another app brought to the front (activated, no click): the
  sidebar starts back in 85 ms later and stays in while the pointer moves on beside the window.
- [U] A second display left of the window; a window in full screen; two windows side by side.
- Cra: `FloatingSidebarGeometry.isOffLeftEdge` (the sidebar's width less its margin, beside the window)
  and `FloatingSidebarOffEdge` (CraCore): armed by a sample over the window or in its strip, the wait
  `offEdgeRest` (0.085 s) from the pointer's last move or `offEdgeLongestWait` (0.15 s) from leaving the
  window, whichever ends first (three and five looks of the 30 Hz poll after the first); `shouldHide` keeps a sidebar that is out while the pointer is in the zone.
  The 30 Hz poll feeds it (`FloatingSidebarController.pointerSample`); the sidebar stages during the wait
  as it does in the strip. When Cra stops being the active app the poll stops, so a sidebar the pointer
  keeps out from beside the window is sent away then (`resignedActive`).
- [O Cra, the same tool and plans, a 322 pt sidebar] Before: nothing comes out past the edge (thrown to
  −100, jumped there, 200–1500 pt/s exits), and a 100 pt/s exit flashes the sidebar 86 pt out and back.
  After: out 131–156 ms after a thrown pointer's last move (Arc 135–160) and 212–240 ms after the edge for
  one that keeps moving (Arc 218–231); stays beside the window, leaves above it, nothing from above, below
  or further left, nothing for out-and-back; gone 28 ms after another app comes to the front. Kept
  apart from Arc: the zone is the window's height (Arc's sits ~24 pt lower), and a 100 pt/s exit comes out
  from the 10 pt strip 60 ms after the edge (Arc's 5 pt strip lets it pass: 220 ms). The reveal's frames
  are Arc's one frame ahead, as on 9 Nov, but never past the resting edge: the panel ended there, so the
  spring's 1.5 % overshoot (Arc: 274 for 270) was cut off.
- [O 1x frames, the same run] Arc's floating sidebar rests ~5.5 pt inside the window (a 264 pt one from
  x 5.5 to 269.5, its top at y 5.5; "5 pt in" in full screen on 10 Nov) and the page starts 10 pt in. At
  the reveal's peak the whole sidebar is 4 pt further right (x 9.5 to 273.5), so its left edge stops at
  the page's edge and only the window's own margin shows beside it. Its stand-in traffic lights are
  centred at x 24.8, 47.3, 70, y ~29 of the window.
- Victor, trying the fix: "the sidebar shoots out too far, I can see some pixels of the background when
  it is most to the right". [O Cra, 2x frames of the scripted reveal, `cra://debug?floatingSidebar=1`] The
  sidebar rested 8 pt in and the 9 Nov spring swung it 6.4 pt (2 % of 325), so at the peak the page showed
  from x 10 to ~13 left of it for three frames, and its right side was cut off at the panel's end while
  the shadow swung on.
- [O] Arc's reveal refitted on 27 of today's reveals (right edge per frame, the end of the motion weighted
  4×, each run's start free within 12 ms; the same result from four starting points, rms 4.8 pt): stiffness
  1134, damping 54, initial velocity 9.1. It lands at 115 ms, peaks at 274.15 at 146 ms (1.54 %) and reads
  271 again at 214 ms; Arc's frames read 274 from 136 to 154 ms and 271 again at 198 ms. The 9 Nov spring
  (759, 46.3, 23.3) peaks at 275.4 and is back at 271 only at 238 ms.
- Cra now: `FloatingSidebarGeometry.margin` 5 (the stand-in lights land on 25, 29), the leave boundary kept
  81 pt past the sidebar's width (`leaveSlack` 76) and the zone beside the window 8 pt narrower than the
  sidebar (`offEdgeShortfall`). `FloatingSidebarSpring` (CraCore) is Arc's spring up to Arc's 270 pt of
  travel; for a wider sidebar the damping goes up just enough to keep the swing at Arc's 4.2 pt (54.9 for
  333 pt), so the sidebar's left edge peaks at 9.2 pt, short of the page at 10, whatever its width. [U]
  whether Arc's own swing grows with a wider sidebar. The panel is the swing + 2 pt wider while the
  spring runs and ends at the resting edge again once it settles.
- [O Cra after, the same 2x capture] Right edge at rest 325.0, peak 329.0, back at 325 within ~0.1 s of the
  peak; in no frame does the page show left of the sidebar.
- Victor, with the window zoomed to the screen: "when I hover to reveal it, the shadow that the Cra window
  drops disappears. Arc's shadow is there all the time." [O Cra, real hover, screen captures] With the
  window at 0, 33, 1728 × 1084 the band above its top edge (the window's shadow, seen through the menu
  bar) goes from dark (0x58 down to 0x33) to flat 0x6c and the black 1 px outline goes, along the whole
  edge, for as long as the sidebar is out; in a window standing clear of the menu bar nothing changes. The
  click-through panel that carries the sidebar's soft shadow reached `shadowPad` past the sidebar, 11 pt
  above the window (8 pt since #293), so it lay under the menu bar, and macOS gives the menu bar its frosted
  backing over any window beneath it. Cra: both floating panels are cut to the window's frame
  (`panelFrame`, `shadowPanelFrame`); what reached past it was masked by the window's outline already
  (#341).

## Copy URL confirmed in place (Arc 1.172.2, 11 Nov 2026, GitHub #361, Victor's Arc, ~115 fps window recordings)

Window recordings (ScreenCaptureKit, one window, no cursor) of AX presses and one real click, on the normal
toolbar's 24 pt "Copy Current URL" glyph (12 pt link), the sidebar URL field's `copyLinkButton` (30 pt box, 14 pt
link, toolbar hidden with ⇧⌘D), a Little Arc's link icon and the developer bar's Copy Link.

- [O static] `CommandBarPlaceholderButtonsView` (the sidebar URL field's buttons) holds a `CopyLinkViewModel`
  { isCopied, foregroundColor, activeColor, copyToken, isSidebarAnchored, isSidebarHovered, isShowingMenu };
  ARCUI's `TranslucentButtonIconAnimation` has a `CopyLinkIcon` beside ReloadIcon and PlusMenuIcon.
- [O] A click on the toolbar glyph or the sidebar's Copy Link: the link shrinks about its centre and fades
  (gone by ~0.10 s); from ~0.17 s a checkmark in the glyph's ink draws itself from the short leg's end to the
  long leg's tip (whole by ~0.31 s) while fading in (opaque by ~0.38 s); it holds until ~1.10 s, un-draws back
  to its short leg over ~0.16 s, and the link springs back from ~0.55 at ~1.26 s, overshooting to ~1.14
  (sidebar) / ~1.17 (toolbar) at ~+0.13 s and settling by ~+0.45 s. The checkmark's ink is a square 0.83 of
  the link's point size (20 px at 2x for the 12 pt link, 24 px for the 14 pt one) on the glyph's centre,
  stroke ~1.6 pt. The hover fill stays as it was; nothing lifts or casts a shadow.
- [O] The "Copied Current URL" toast shows with it (top right of the page). ⇧⌘C and Edit ▸ Copy URL show only
  the toast and leave the glyph alone, with the pointer over the sidebar field or not; so do a Little Arc's
  link icon and the developer bar's Copy Link (which never animate).
- Cra: CraCore `CopyCheck` (the numbers), `NSImageView.playCopyCheck` (CopyCheckAnimation.swift), played by
  the sidebar URL field's Copy Link and `ToolbarURLButton.copyFromGlyph`; not by ⇧⌘C, the Little Window or
  the developer bar.

## ⌘W in the Settings window (Arc 1.172.2, build 90755, 11 Nov 2026, PR #364, arm64 static analysis)

- [O] `Settings.SettingsWindowController` (an `NSWindowController`) implements `closeCurrentItem:`, the
  action behind Arc's ⌘W (File ▸ Close Tab), next to `doCommandBySelector:`, `copyAction:` and
  `supplementalTargetForAction:sender:` (`otool -oV` on the arm64 slice, selector refs resolved through
  `__objc_methname`). Its window class is `Settings.UserInteractionPausableWindow`.
  [I] With Settings key, ⌘W reaches Settings first and closes it; the browser window behind keeps its tab.
  Same pattern as `BrowserExtensionWindowController.closeCurrentItem:` (extension windows).
- Cra: `AppDelegate.perform(_:)` sends Close Tab and Close Window to Settings while it's in front
  (`settingsInFront`); with a sheet up on Settings nothing closes. Scenario `settings-close-shortcut`.

## Permission requests (Arc 1.172.2, 12 Nov 2026, GitHub #371, a Little Arc asking for MIDI, 2x window capture)
- [O static] `PermissionRequests/PermissionRequestPopoverView.swift` and `PermissionRequestDialogView`. Strings:
  "Allow %@ to access your %@?" (the site's title, else "this website"; the type's `displayName`, e.g. "local
  network", "MIDI devices"), own sentences for notifications, multiple downloads, storage, idle detection and
  mailto ("Make %@ your default mail app?"), "Click the lock to change this any time", "Button to deny permission".
- [O] Not a sheet and no arrow: a card over the page's top left corner, 12 pt in from the page's left edge and
  12 pt under the toolbar. The page and the window stay usable while it is up.
- [O] Card 232 pt wide, 126 pt tall with a two-line question, #050627, ~10 pt corners, a soft shadow (about
  25 % black, 8 pt blur, 3 pt down). Badge 24 pt (#090D4F, 4 pt corners, the `info` glyph in #ECEDFF) 16 pt in,
  20 pt down. Question 13 pt semibold white from 48 pt in, 16 pt lines, centred on the badge. "Click the 🔒 to
  change this any time" 11 pt medium white, 16 pt in, 8 pt under the question. Buttons 96 × 32 pt, 8 pt apart,
  16 pt from the sides, 22 pt under the hint, 16 pt above the bottom, 5 pt corners, 13 pt semibold labels: Not
  Now (no fill, a 1 pt #2A2B47 lip) on the left, Allow (#434BDF, a 1 pt #232441 lip) on the right.
- Not measured: hover and pressed colours, light mode, where the card sits in a main window with the sidebar,
  what Not Now saves.
- Cra (#371): `PermissionPopover` (a child panel over the tab's `webArea`, the Little Window's page), Arc's
  layout and colours. A tab switch takes it down unanswered and it asks again when the tab is back
  (`PermissionAsk.stepsAside`). Cra keeps its own question ("<origin> wants to …", locked by #137 and #286).
  `cra://debug?permissionCard[=<button>]`, scenario permission-card.
