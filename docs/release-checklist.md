# Release checklist

Most closed issues are pinned by a locked test (rule 8 in [testing.md](testing.md),
`Tests/promises.lock`). This page covers the rest: what only a person can check in a real
window (a real site, the GPU, full-screen Spaces, how something feels), and the issues still
waiting for a hook or a move into CraCore before a test can pin them.

Before tagging a release, run through the checks for every area the release touched, on the
built release app with a test profile. Note anything that fails in the release's issue or PR.

## Manual checks

### Themes and window chrome

- **#155:** a space on Auto, with one colour or two, changes look when macOS switches between
  light and dark. A space on Light or Dark doesn't.
- **#37:** over scrolling text, the sidebar stays blurred in every frame, with no hover.
- **#83, #132:** activating the window shows a flat fill for a moment, never a sharp unblurred
  frame. In full screen a solid space sits on the wallpaper tint, not near-black.
- **#156:** with Reduce transparency on, the sidebar is one flat colour across activations and
  swipes. With it off, a Dock restore and Stage Manager show no matte frame, and a ⌃←/⌃→
  full-screen round trip doesn't step.
- **#46:** waking a slept tab in dark mode shows a black page area, not white.
- **#6:** a new window's empty card has rounded corners.
- **#24:** edge to edge, there is no margin and the card is square, with the sidebar shown and
  hidden.
- **#10:** neighbouring tab highlights keep a 5 pt gap.
- **#11:** the Library glyph is centred in its hover square.
- **#39:** the header chevron is about 12.5 pt and points right when the pinned tabs are
  collapsed.
- **#31, #48:** the tab-list scroller shows a 4 pt knob 3 pt from the edge with "When
  scrolling", and a 5 pt knob with "Always".
- **#189:** colour swatches grow on hover and shrink when pressed; "Back to Pinned URL" slides
  in over 0.16 s.
- **#88:** importing from Arc copies its Show Full URL setting.
- **PR #269:** in Settings, the selected source-list row is inset 10 pt from both sidebar edges
  (glyph 20 pt and label 49 pt from the edge, as in Dia 1.55.1), and scrolling Performance or Advanced
  never draws under the back/forward pill or the pane title.

### Sidebar, tabs and the command bar

- **PR #268, ⌘T:** next to Arc on a themed space and on a default one: the selected row is the
  space's colour (gold on a gold space), white text and a white arrow tile; the info badge takes the
  space's darkest tone. Recent open tabs show "Switch to Tab" before typing. Arrow through results
  and check every row's inks follow the selection; long titles truncate before the trailing action.

- **PR #324, 5-Second Previews:** with Apple Intelligence on and Settings ▸ Max ▸ 5-Second Previews
  on, rest 1 s on a story title on Hacker News, a Google result and a link in a post on X: a loading
  card hangs under the link, then the answer streams in (picture, bold line, 2–4 rows), next to Arc's
  on the same link (arc-reverse-engineering.md has its measurements). A story's "comments" link, a
  Google side-panel link and a plain hover on any other site show nothing; Shift held as the pointer
  reaches a link shows the answer, or the small card for a link within the site. Leaving the link
  closes it at once unless the pointer is on the card. Share ▸ Copy as Text and Copy as Image paste as
  Arc's do. Check a beige and a dark space, 1x and 2x.

- **Music notes:** on a release build, play a favorite on YouTube Music, SoundCloud or Spotify.
  Compare Arc and Cra in light and dark spaces at 1x and 2x: origin, density, speed, growth, fading
  and clipping. Notes rise from the icon's top edge and stop 8 pt above the top row; in lower rows
  they drift over the tile above. Check split favorites in both orientations, dragging, space
  swipes and a space with no favorites for clipping regressions. Mute or pause: notes disappear
  as sound stops; a quick resume brings them back. A regular YouTube video shows none. Toggle
  Reduce Motion during playback: notes disappear and return when it is off. Dark footage, light
  screenshots and live pause/resume were checked on 10 Nov; full-window 1x/2x and the other states
  remain. Arc's mute and Reduce Motion behavior are unverified; record differences when comparing.

- **#196:** hover a Today tab and move onto its ✕ several times. The ✕ never vanishes before
  the click.
- **#7:** click a tab while moving the pointer a few points on a trackpad. It opens.
- **#3, #208:** a middle click on a sidebar tab row closes it; one in a page never does. ⇧⌘J
  opens Downloads in the sidebar; Esc or the back arrow closes the Library.
- **#233:** with a real mouse, its back button over the sidebar goes to the previous space and
  forward to the next, docked and in the hidden sidebar (⌘S); over a page they still go back and
  forward in the tab's history. A mouse that emits button 3/4 does this on mouse-up. An MX Master
  with Logi Options+ does not: set Back/Forward to the keystrokes ⌥← and ⌥→ (a plain shortcut, not
  the smart Back gesture) on the Cra profile. Console should log `Cra: mouse key back:`. The
  scenario never sees a real button or that key, so only this check proves the monitor does.
- **#260:** on a built-in trackpad, every space change by a two-finger swipe over the sidebar
  ticks once: a short flick, a slow drag past half (the tick comes at half), and a swipe into
  the Library and back out. A short drag that settles back is silent; a sideways wheel never
  ticks (Arc). `PageDetentHaptics` holds the rule; only a finger feels the tick.
- **#12:** a two-finger swipe in the hidden sidebar (⌘S) switches spaces, and the next space
  draws mid-swipe. There is one link bubble only, and the dashed ring shows only on a
  cross-space keyboard switch.
- **#28:** the speaker sits between favicon and title, a click mutes, and it doesn't blink
  between tracks.
- **#47:** ⌘T highlights the New Tab row; the list scrolls only enough to show the active row.
- **#85:** ⌘Return keeps the bar open; the "New Tab Created" toast shows only while the sidebar
  is hidden.
- **#92:** in a Little Window, ⌃⌘2 sends the page to the window already on space 2.
- **#174:** with a page text field focused, ⌘Space switches input source and ⌘` switches
  windows.
- **#194:** in Google Docs, ⇧⌘C copies the URL instead of opening Word count; DevTools still
  gets ⇧⌘C.
- **#192:** in a page's rich text field, ⇧⌘V pastes plain text and Edit ▸ Paste and Match Style
  is enabled.
- **#33:** hover the player stack: check the volume slider, the Picture in Picture button, and
  the light card in a light space.

### Peek, Little Window, Picture in Picture, split view, Capture

- **PR #221:** opening a Peek fades the page behind and draws it back a little, its margins widening
  while the sidebar stays still, and closing brings it back in one smooth motion with no jump at the
  end. With "Pages fill the window edge to edge" on, the page only fades. (The values are checked
  by the peek-backdrop scenario; this is the motion.)
- **#195:** in a Peek and a Little Window, click in the page, then Back, Forward, Refresh, the
  address and "Open in": each works on the first click. Capture and scroll: the page moves and
  the grey picture and the lens follow. With another app full screen, ⌥⌘N opens a Little
  Window over it, and doesn't when Settings ▸ Tabs ▸ Links is off.
- **#202:** in a Peek, ⌘-click a `target=_blank` link: a background tab opens and the Peek
  stays. A plain click on it takes the Peek away and selects the new tab below the source tab.
- **#242:** Peek a link from a pinned tab, scroll the Peek, click a `target=_blank` link in it: the
  new tab shows with no Peek and the pinned row keeps the peeked page's favicon. Click the pinned
  row: the same Peek is back at the same scroll, the page behind faded, and clicks in it work.
  With the Peek shown, click another tab's row: that tab opens (the Peek waits); a click on the
  faded page beside the card closes it. (Which Peek shows when is the peek-per-tab scenario;
  this is the look, the scroll and the real clicks.)
- **PR #222:** with a Peek open, the browser window keeps its full shadow and coloured traffic
  lights, also after a click in the Peek, as in Arc. A drag from every edge and corner resizes the
  window with the Peek open and the card follows; a click on the background 4 pt or more inside
  the window closes it.
- **#186:** send a link from a full-screen app. The Little Window opens centred on that Space
  with no switch to the desktop, and a video in it can still go full screen.
- **#231:** with Keep Cra in the menu bar on, the C shows in the menu bar in light and dark.
  ⌘Q takes the windows and the Dock icon away, and focus goes to the app behind. A full-screen
  window leaves its Space first. ⌥⌘N from another app opens a Little Window at once, with the
  Dock icon. Closing it takes the icon away again. New Window in the item's menu brings the
  windows back, and Quit Cra there quits.
- **#319:** with a custom app icon and Keep Cra in the menu bar on, ⌘Q, then New Window from the
  item's menu: ⌘-Tab and the Dock show the custom icon, not Segments
  (app-icon-dock-return.scenario only sees that Cra set it again).
- **#298:** in a tab on a DRM service (it opens in WebKit, docs/protected-media.md), Option-click a
  link: it opens as a split pane beside the page, as it does in any other tab (that scenario's
  posted click never reaches a WebKit page behind other windows).
- **#172:** with a space on its own profile, a Little Window from that space and a Peek from its
  tab see that profile's cookies. The chip names the profile; switching it reloads the page in
  the other profile.
- **#329:** a Little Window's strip is a gradient, deep blue-grey at the left to purple-grey at the
  right, in every space (compare Arc 1.172.1 beside it). Its traffic lights are grey with the window
  in front and the pointer elsewhere, and red, yellow and green with glyphs while the pointer is over
  them. The address pill is a lighter wash over the strip, also under the pointer.
- **#330:** the address pill reads the host only (no port, path or query). An http page shows an
  orange open padlock on a pale orange tile where the magnifier is; an https page and a blank one
  show the magnifier, and so does a window still waiting for its first response.
- **#206:** a video's PiP and Meet's PiP stay on top over a full-screen app, and clicking or
  dragging them doesn't bring Cra forward.
- **#198:** in a Meet call with automatic picture-in-picture on, leaving the tab opens Meet's
  PiP and coming back closes it. The tab shows the recording dot and doesn't sleep.
- **#134:** with another app in front, the PiP edges show resize cursors, and a click on play
  doesn't move the window.
- **#246:** a YouTube video's PiP shows no Chrome strip (site icon, host, dark top band) at any
  point, also in the first seconds; with the pointer away it is the bare video. On hover: Back to
  Tab on the left (with its words from 400 pt wide), the host centred and whole, Close on the
  right, one even dim layer.
- **#262:** hover a YouTube PiP after a drag on its edges, a resize, a trip to another app's
  full-screen Space and back, and a click on Cra's window: only Cra's controls show (no grey ±10,
  no second ✕, no scrubber). Play/pause alone in a window under 280 pt wide, with the ±15 pair
  and a bigger play/pause from 280 pt; `cra.log` has no "Chromium's window became key".
- **#178:** in a split, the focused pane's ring shows (also over docked DevTools), and so does
  the card shadow.
- **#90:** Capture on a second display and behind other windows isn't blank. It goes to the
  clipboard with the "Screenshot Copied to Clipboard" toast, and Save offers Downloads.
  Full-page capture shows "Capture in Progress" first. Share keeps the control center open. On
  an https page with a certificate error the lock reads "Not Secure" and opens the certificate
  sheet.

### Extensions and developer mode

- **#203:** import a store extension from Arc, open a page, then reload the extension in
  `chrome://extensions`: it stays on and shows as from the Web Store. "Add to Chrome" puts
  nothing in `~/Downloads` and shows no save panel.
- **#43:** Load unpacked in `chrome://extensions`. The extension shows in the open Extensions
  popover within about 1 s, and so does an on/off switch.
- **#41:** on a test copy, `Extensions.triggerAction` on a turned-off extension answers "No
  enabled extension…" instead of crashing.
- **#8:** a Bitwarden popup opens in under 0.5 s and hangs from the button's right edge. A
  dragged popup reopens at the same offset after the window moves.
- **#38:** in full screen, SwitchyOmega's Options doesn't slide the Space away, and a second
  click selects the open options tab.
- **#42:** clicking the URL in the developer bar edits it in place with the whole URL selected
  (Return loads, Esc cancels). A long press on the Extensions button doesn't close and reopen
  the popover.
- **#9:** for a pinned extension, Monochrome, Symbol, Choose Image… and Original Icon each work
  and survive a restart.
- **#89:** in developer mode the ⌄ chevron lists Refresh ⌘R, Force Refresh ⇧⌘R, Clear Cookies
  and Refresh, Clear Cache and Refresh, View Source ⌥⌘U and Developer Tools ⌥⌘I. Tab row
  context menus show their shortcuts.
- **#265:** signed in to a paid Claude plan, Claude in Chrome's toolbar button opens its panel
  and Claude works in it: no "Claude isn't available on this page" and no "Can't reach Claude
  in Chrome". The scenario covers what the extension checks, but only an account gets past
  claude.ai's sign-in.

### Profiles, privacy, media and the engine

- **#111:** reset Cra's camera access (`tccutil reset Camera <bundle id>`), open Meet, click "Use
  microphone and camera" and Allow. One Cra prompt shows, then macOS's own dialog, and nothing
  crashes.
- **#36:** on a new data folder, finish onboarding with an Arc import that brings extensions and
  passwords, so Cra relaunches. The quitting process leaves no crash report.
- **#5:** with Cra running, `ps -axo args | grep 'Cra Helper'`: the renderer, GPU, network,
  storage and audio helpers carry `--seatbelt-client`; only video capture runs without it.
- **#66:** signed in, a Disney+ title and a Prime Video title both play, in Safari's engine.
- **#167:** on a Mac whose first language is Simplified Chinese, cra.log says `chromium locale:
  zh-CN` and chrome://version shows `--lang=zh-CN`.
- **#133:** pick Google in Settings ▸ Privacy ▸ Secure DNS. Without a relaunch, cra.log says
  `secure dns: secure via dns.google` and chrome://settings/security shows the same choice.
- **#190:** with Ask Where to Save Each File on, the save panel is a sheet on Cra's window, and
  Cancel cancels the download.
- **#272:** download a large file. The bin over the Library button keeps a ring that fills as it
  downloads; right-clicking its row in the tray and on Library ▸ Downloads offers Pause Download and
  Cancel Download, and a paused row reads "Paused". ⌘Q while it runs asks "Downloads in progress";
  Keep browsing keeps it going. Once it finishes, a check replaces the arrow, and its row's menu
  reads Open / Copy <kind>, Show in Finder, Hide from Cra and Move to Trash.
- **PR #254:** with the release app as the default browser, open a page in Safari on an iPhone
  signed in to the same Apple Account and click the Handoff icon in the Dock. The page opens in
  Cra, in the space Air Traffic Control picks, and not in Safari.
- **#261, #195:** with Stage Manager on, use Cra full screen with 20 or more visited tabs for ten
  minutes. No grey pane flashes and Stage Manager shows no window coming and going. After a
  minute pass, the GPU helper's footprint (`footprint -p <pid>`) still drops as the hidden tabs
  let go of their tiles (#195: 20 tabs, 386 → about 235 MB).
- **#308:** in full screen, drag the toolbar, the sidebar's top strip and the page's margin by
  hand. The window stays put. With the sidebar hidden, the pointer at the top of the screen
  reveals the title bar with the traffic lights in it. The `fullscreen-window-chrome` scenario
  checks the window's flags; only a hand drag shows that AppKit honours them.

## Not pinned yet

Each of these needs a change to production code before a test can pin it: a move into
CraCore (rule 1 in CLAUDE.md), or a `cra://debug` hook a scenario can read. Do the one for an
issue when a change touches that code anyway.

| Issue | What would let a test pin it |
|---|---|
| #202 | Move where a link's tab lands (`BrowserManager.openLinkTab`) into CraCore, e.g. a `LinkTabPlacement` value |
| #172 | Move the Little Window's profile order (opener's page, Peek's tab, target space) out of `LittleWindowController.init`; or a `littleProfile` hook logging its profile folder |
| #186 | `cra://open?…&little=1` honours `CRA_TEST_BACKGROUND`, and `debug?windows=1` logs `collectionBehavior` |
| #178 | Split panes keep their bars with the toolbar hidden (`ShellView.barsShown`), and View ▸ Show Toolbar is disabled in a split: both in files no harness compiles |
| #191 | Move the drop-target rule (a tab over a row's middle splits, never into a folder) out of `SpaceListView` |
| #47 | Move `SpaceListView.revealActiveRow` (scroll the least that shows the row) |
| #139 | Move `navigatedAway` (pinned, URL differs from the saved one) out of `SpaceListView` |
| #3 #21 #86 #195 | Default bindings (⇧⌘J, ⌃⌘1–9, ⇧⌘T, ⌥⌘N) live in `App/KeyBindings.swift`, a known exception |
| #194 | `AppDelegate.reservedActions` must hold `copyURL` and `copyURLMarkdown`: a `reserved=<action>` hook or a move |
| #192 | A `validate=pasteAsPlainText` hook logging whether the item is enabled while a page has focus |
| #21 | An `undoKey` hook logging whether ⌘Z undoes typing or reopens a tab |
| #49 | `SuggestionEngine` (at most five rows, never the current tab), a known exception |
| #171 | `themeShown` also logs the window's appearance and effective appearance (menus and sheets follow it) |
| #187 | `themeShown` also logs the command bar's appearance and highlight colour |
| #152 | `spaceTip=<n>` logs the tip's text, profile pill and caps |
| #40 #170 | `spaceMenu=1` logs the space header menu's items in order, and the list's right-click menu too |
| #132 #156 | A `windowActive=0\|1` override, since a background scenario window is always "blur, active" |
| #22 | Move `ExtensionStore.Entry.isInstalled` and `isEnabled(inProfile:)` into CraCore |
| #106 | Move the action icon fallback (`default_icon` as a dict or string, else `icons`) into CraCore |
| #9 | Move `IconStyle` into CraCore with a fixture; or `pinExtension` and `extensionIconStyle` hooks plus a toolbar snapshot |
| #89 | A `menuItemsAt=x,y` hook logging each item's title and shortcut |
| #8 | Move `ExtensionPopupWindow.placement(anchor:width:)` and the drag offset into CraCore |
| #137 | A cra.log line when the permission sheet shows (`permission sheet <host>: <kinds> (tab\|little)`), so a scenario can show a Little Window asks for notifications |
| #5 | A `processes` hook logging each helper's `--type=` and whether it runs under the sandbox |
