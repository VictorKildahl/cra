# Release checklist

Most closed issues are pinned by a locked test (rule 8 in [testing.md](testing.md),
`Tests/promises.lock`). This page covers the rest: what only a person can check in a real
window (a real site, the GPU, full-screen Spaces, how something feels), and the issues still
waiting for a hook or a move into CraCore before a test can pin them.

Before tagging a release, run through the checks for every area the release touched, on the
built release app with a test profile. Note anything that fails in the release's issue or PR.

## Manual checks

### Themes and window chrome

- **#739:** with Settings ▸ General ▸ App Icon on Segments (check `defaults read dk.kildahl.cra appIcon`: a pick is
  drawn as it is, by design), System Settings ▸ Appearance ▸ Icon & widget style set to Dark, then Clear and Tinted,
  turns Cra's Dock icon dark, glassy and tinted like the other apps' (the Icon Composer icon, resources/AppIcon.icon,
  compiled into Assets.car; AppIconCatalogTests). Default is Gilad's white glass tile. On macOS 14 or 15 the .icns
  rendered from the same icon shows. Built on Xcode 27, check it on macOS 26 too, not only 27.
- **#372:** Settings opens at 684 × 650 pt on the first tab (your first name, "Cra" without one) every time, whatever tab it was closed on, and ⌘W closes it. Go through the
  ten tabs in dark and in light: the window is the system's window colour (not Arc's navy, Victor 12 Nov 2026), the chosen tab's pill
  (white 10 % with a hairline in dark, white with a shadow in light), 36 × 16 pt switches, the cards, Max's banner (Cra's mark and "Max"),
  Links' picture, Shortcuts' key caps and search ("command e"), Icon's radio list, Profiles' list beside its cards. Switching tabs is
  instant: nothing fades or resizes. The first tab: the default-browser banner (only while Cra isn't the default), the member card (your macOS
  name, its colour and nickname, EARLY '26, a months stamp after a month), Share / Save / Copy under it (the saved PNG is the card at 2x),
  and Share Cra: the sheet's COPY LINK puts the tagged crabrowser.app link on the clipboard and Share… offers Messages and Mail. (The scenario checks the
  size, the tab order and the first tab; this is how it looks.)
- **Displays:** On a Mac with two displays of different scale (a 2x and a 1x), drag the window from one display to the other and
  back, several times, by the strip above the toolbar, by the toolbar's URL and by the sidebar's top next to the traffic lights:
  the window stays under the pointer the whole way, with no jump at the crossing and no flicker. AppKit's screen-layout adjustment
  ran mid-drag for a window a window controller owns (16 Nov 2026); `CraWindow` skips it for moves the window server reports. The
  `window-frame-adjust` scenario only checks that answer is in place; a test copy never crosses a display. After the drag, open a
  `<select>` on a page: its menu opens on the control, not a display's width away (21 Nov 2026). The
  `window-frame-after-move` scenario sends the window the server's report of such a move, not a real drag.

- **#155:** a space on Auto, with one colour or two, changes look when macOS switches between
  light and dark. A space on Light or Dark doesn't.
- **#37:** over scrolling text, the sidebar stays blurred in every frame, with no hover.
- **#83, #132:** activating the window shows a flat fill for a moment, never a sharp unblurred
  frame. In full screen a solid space sits on the wallpaper tint, not near-black.
- **#156:** with Reduce transparency on, the sidebar is one flat colour across activations and
  swipes. With it off, a Dock restore and Stage Manager show no matte frame, and a ⌃←/⌃→
  full-screen round trip doesn't step.
- **#46:** waking a slept tab in dark mode shows a black page area, not white.
- **#6, #483:** a new window's empty card has rounded corners, is white over the space's colour
  (stronger in light themes and faint in dark), casts the page card's soft shadow, and remains
  below the find and status bars.
- **#24:** edge to edge, there is no margin and the card is square, with the sidebar shown and
  hidden.
- **#464:** with Settings ▸ Tabs ▸ Sidebar on the right, the sidebar and its traffic lights sit on the
  right, ⌘S slides it out to the right and back, and dragging its left edge resizes it (snap and
  drag-to-hide too). Hidden, the right edge brings it out on Arc's spring with its shadow and the
  window's rounded corners clipping it; folder, pinned-tab and favorite previews open to its left.
  (The scenario checks where things are; this is how the motion looks.)
- **#10:** neighbouring tab highlights keep a 5 pt gap.
- **#11:** the Library glyph is centred in its hover square.
- **#39:** the header chevron is about 12.5 pt and points right when the pinned tabs are
  collapsed.
- **#31, #48:** the tab-list scroller shows a 4 pt knob 3 pt from the edge with "When
  scrolling", and a 5 pt knob with "Always".
- **#544:** with "When scrolling", flick a long tab list up and down on the trackpad, touching down
  again while it still glides: the knob stays up the whole time, without blinking at each touch, and a
  two-finger swipe between spaces from a list at rest shows no knob. (`ListKnobGate` decides; no test
  can post a trackpad gesture's phases.)
- **#189:** colour swatches grow on hover and shrink when pressed; "Back to Pinned URL" slides
  in over 0.16 s.
- **#88:** importing from Arc copies its Show Full URL setting.
- **PR #269:** in Settings, the selected source-list row is inset 10 pt from both sidebar edges
  (glyph 20 pt and label 49 pt from the edge, as in Dia 1.55.1), and scrolling Performance or Advanced
  never draws under the back/forward pill or the pane title.
- **#701:** open an extension's popup from the toolbar (Element Remover or 1Password) on macOS 26 and 27: the page
  sits inside the window's thin border on both sides and the bottom, and its bottom corners follow the window's
  rounded ones (no square corner past the border). The scenario checks the geometry and the mask; the pixels need an eye.
- **#701, Inspect:** right-click inside an extension's popup (Bitwarden, 1Password) and choose Inspect: Chromium's
  DevTools window opens on the popup and the popup stays open while you click around DevTools; a click in a Cra
  window then closes it. The harness covers the focus rule with a stand-in window; the real Inspect needs a hand.
- **#400 (macOS 27 only):** a white page with DevTools docked right and set to dark, toolbar shown,
  Edge to edge on and off: no white shows at any corner of the page or DevTools. This Mac runs
  macOS 26, where the test stands in for 27 with AppKit's own window radius; ask the reporter to confirm.
- **#533 (macOS 27 only):** Cra alone on a second display playing a YouTube video with sound; click
  another app on the first display: the video keeps playing in its tab. Cover Cra's window with
  another app, or minimise it: the video goes to Picture in Picture. macOS 26 never called the window
  not visible here, so WindowCoverageTests and `window-coverage-own-parts` stand in; ask the reporter.
- **#550 (macOS 27 only):** in macOS full screen with the sidebar hidden, bring it out over a white
  page and a pink one: its top rests 5 pt below the screen's edge and its shadow touches it all round,
  with no strip of page colour above it. macOS 26 places the panels right without the fix, so
  FloatingSidebarTests (AppKit's own constraint) and `floating-sidebar-shadow` stand in; ask the reporter.

### Boosts

- **#478:** open a Boost on a page of dark and light text, tint it, then drag the small wheel handle
  away from the big one: only the small handle moves, dark pixels change hue and light ones keep the
  big handle's hue. Drag the big handle afterwards: the offset between them stays. The connector
  follows the orbit and keeps its direction past half a turn. Either dot has three sizes: at rest,
  larger under the pointer, and largest while held and hovered, with no pointer change. CraCore pins
  the geometry and the colourize; only the gesture and the hover animation need a person to watch them.
- **PR #889:** open the Boost editor beside Arc's on the same site, untinted and then tinted: the frame's
  width and corners, the ring's colours, the dot grid, the faint colour wash on the face and the hairline
  round each handle look the same. CraCore pins the ring's colour stops; the drawing needs an eye.

### Sidebar, tabs and the command bar

- **#794:** with Japanese (Romaji) input on, the Kana key (or Karabiner's ⌘ tap that sends it) switches to Japanese and Eisu back,
  in the command bar, a tab's rename field and the find bar as on a web page (kana-key-cra-fields checks the routing).
- **#483:** with no selected tab and the sidebar saved hidden, it comes straight out floating and
  stays visible when the pointer leaves and when another app comes to the front. Its button switches
  between docked and floating. Open a page: it remains while the pointer is over it, then slides away
  when the pointer leaves. Switch to an empty space and it comes straight back.
- **#483, docking:** dock the sidebar from floating over both the empty card and a real page. It grows
  into place, its corners square and its shadow fades without the page jumping. Undocking in the empty
  window still snaps to floating; smoothing that direction is a follow-up.

- **PR #268, ⌘T:** next to Arc on a themed space and on a default one: the selected row is the
  space's colour (gold on a gold space), white text and a white arrow tile; the info badge takes the
  space's darkest tone. Recent open tabs show "Switch to Tab" before typing. Arrow through results
  and check every row's inks follow the selection; long titles truncate before the trailing action.

- **#419/#422, insertion line:** drag a tab between two Today rows, then a page's link, with a real
  pointer, on a dark space and a light one: a hollow ring 2 pt before the favicons, then a line to 3 pt
  inside the row, near-white on dark. Put it next to Arc's on the same spaces; Arc's ink was measured
  only on a dark space (#EFEFEC over #383830), so check the light one.

- **#393, Ask on Page:** with Apple Intelligence on and Settings ▸ Max ▸ Ask on Page on, press ⌘F on a
  long article: the card reads "Find or ask…"; typing a word finds it (count, ↑ ↓, highlights in the
  page). Type a question: Return asks once the count says 0 (Ask asks at once). The question in the space's
  colour, "This page was long, so I read the first N%.", an answer with its key words in bold and a quote on
  a rule. Find on Page selects and scrolls to the whole quote in the page, also one across a Wikipedia "[3]";
  a quote the page doesn't have says "Quote not found" when the answer is done. Ask a follow-up; past 450 pt the conversation scrolls
  with fades. Esc or ✕ closes it and the next ⌘F starts over. Compare with Arc's card on the same page
  (Arc's own numbers are in arc-reverse-engineering.md; its placement, corner and colours weren't read).

- **#417, Ask on Page follow-ups:** on a long article ask something the page can't answer ("why did el
  salvador succeed?"), then "Summarize the key points of this article in bullet points": the second answer
  is a summary, not the first answer again, and no answer starts with "BEGIN DIALOGUE", "Human:" or a made-up
  question. Then a factual follow-up gets its own quote. The model is on-device and varies, so ask a few times.
  On a release-notes page (crabrowser.app's 0.1.43 notes), ask "summarize the top features", then "list out
  all the features released today": each answer is a list of at most eight short points, one per line, with
  no quotes and no Find on Page, naming more than the first feature and no point twice. "Summarize it with
  quotes" still quotes the page.

- **Ask on Page, long answers and unanswerable questions:** ask a long article something it doesn't say
  ("why did el salvador succeed?"): the answer never quotes a solar-power page or J.W. Peters. Known on
  the on-device model (16 Nov 2026): it often adds page quotes that don't answer such a question, and it
  refuses some topics (slavery, disasters, religion) with "Sorry, I encountered an error". Ask for "the
  key points of this entire article in detailed bullet points": the window and the page keep scrolling smoothly
  while it writes, and the answer never vanishes and starts over.

- **#407, Instant Links:** with Apple Intelligence on and Settings ▸ Max ▸ Instant Links on, type
  "top 3 pizza places in naples" in ⌘T and press Shift-Return: the bar closes, "Searching the web for you…"
  shows at the top of Today with the flower turning once a second and the selected row's fill, and about 3 s later
  three tabs of real Google results replace it, the first selected. Try "greek and italian restaurants in a
  split" (a split of two at the top of Today), "folder of ramen recipes" (a folder of 5 at the end of Pinned,
  named after the phrase) and an Italian phrase ("le 4 migliori piste da sci in friuli": 4 tabs). Return on the
  same text still searches normally, and with the setting off Shift-Return does too. Run it in a fresh profile
  for the first run (the model's first answer is slower), in an incognito space (the engine's own results page
  opens) and with Reduce Motion on (the flower stands still). Put the row and the flower next to Arc's on the
  same phrase. Find a phrase the model refuses (a guardrail's false positive: "youtube mkbhd" did once) or one
  in a language it doesn't support, and check it opens the phrase as a plain search, not the error row.
  Google blocks hidden pages now and then: with its page unreadable (a captcha or `/sorry`) a search opens
  Google's results page as one tab, whatever the count, and four searches at once in one profile ("greek, italian,
  thai and indian restaurants in a split") can trip Google's `/sorry`, so try that once and note what opened.

- **PR #324, 5-Second Previews:** with Apple Intelligence on and Settings ▸ Max ▸ 5-Second Previews
  on, rest 1 s on a story title on Hacker News, a Google result and a link in a post on X: a loading
  card hangs under the link, then the answer streams in (picture, bold line, 2–4 rows), next to Arc's
  on the same link (arc-reverse-engineering.md has its measurements). A story's "comments" link, a
  Google side-panel link and a plain hover on any other site show nothing; Shift held as the pointer
  reaches a link shows the answer, or the small card for a link within the site. Leaving the link
  closes it at once unless the pointer is on the card. Share ▸ Copy as Text and Copy as Image paste as
  Arc's do. Check a beige and a dark space, 1x and 2x.

- **Music notes:** on a release build, play a favorite on YouTube Music, SoundCloud or Spotify
  (the 1x/2x side-by-side with Arc used nts.live and a local tone, 11–12 Nov). Notes rise from the
  icon's top edge, stop 8 pt above the top row and in lower rows drift over the tile above. Pause:
  they go at once, and a quick resume brings them back. Mute and Reduce Motion: they keep floating,
  as Arc's do. A regular YouTube video shows none. By hand: split favorites in both orientations,
  dragging a playing favorite, space swipes and a space with no favorites, for clipping
  regressions. If notes look denser or wider than Arc's, take a minute-long recording of each.

- **#196:** hover a Today tab and move onto its ✕ several times. The ✕ never vanishes before
  the click.
- **#7:** click a tab while moving the pointer a few points on a trackpad. It opens.
- **#429:** two windows on pages with a text field. Press ⌘L in the first, then click the second's
  field without closing the bar, and type and paste. The text lands in the second window, never the
  first. Do the same from a Little Window's bar.
- **#551:** ⌘T, type part of an address, ⌘Tab to another app and back. The bar is still open with
  what was typed and takes typing at once; while the other app was in front it stayed behind that
  app's windows. Leave again and come back by clicking the page: the bar closes. Same with ⌘L in a
  Little Window.
- **Row press:** next to Arc, hold the button on a pinned tab, a Today tab, a split, New Tab and a
  Favorites tile. Each pushes in slightly about its centre (a tile a little more) and springs back
  on release; a drag doesn't leave it pushed in, a double-click on a tab dips once, folders don't move.
- **#3, #208:** a middle click on a sidebar tab row closes it; one in a page never does. ⇧⌘J
  opens Downloads in the sidebar; Esc or the back arrow closes the Library.
- **#233:** with a real mouse, its back button over the sidebar goes to the previous space and
  forward to the next, docked and in the hidden sidebar (⌘S); over a page they still go back and
  forward in the tab's history. A mouse that emits button 3/4 does this on mouse-up. An MX Master
  with Logi Options+ does not: set Back/Forward to the keystrokes ⌥← and ⌥→ (a plain shortcut, not
  the smart Back gesture) on the Cra profile. Console should log `Cra: mouse key back:`. The
  scenario never sees a real button or that key, so only this check proves the monitor does.
  With Options+'s own Back and Forward assignments (the gesture, an MX Ergo's default) the same
  holds: Console logs `Cra: mouse swipe back:`. In Split View the pane under the pointer goes back,
  not the focused one, and a tab a link opened closes back to its opener. A test can't make a swipe
  event, so only this check proves the swipe monitor.
- **#714:** ⌥← / ⌥→ typed on the keyboard reach the page: on a YouTube video with chapters they skip to the
  previous and next chapter, and the tab stays (Console: `Cra: mouse key back: left for the page, typed on the
  keyboard`). Then the #233 check above with Logi Options+'s ⌥← / ⌥→ keystrokes: they must still go back and
  forward, which proves Options+ posts them from its own process (an event from the keyboard has source process 0).
  If Options+ types them as a keyboard does, they reach the page instead and #233's keystroke assignment needs
  another tell.
- **#260:** on a built-in trackpad, every space change by a two-finger swipe over the sidebar
  ticks once: a short flick, a slow drag past half (the tick comes at half), and a swipe into
  the Library and back out. A short drag that settles back is silent; a sideways wheel never
  ticks (Arc). `PageDetentHaptics` holds the rule; only a finger feels the tick.
- **#370:** on a built-in trackpad, click a link that opens a new tab, then swipe back with two
  fingers over its page: Chromium's back arrow shows, and letting go closes the tab and shows the
  one the link was clicked in, as the Back button does. On a pinned tab or a split pane with no
  history the arrow never shows; a tab with pages behind it swipes through those first. The
  `swipe-back` scenario asks the swipe's two questions (`cra://debug?swipeBack=`); only a finger
  makes the gesture.
- **#495:** open a Little Window (⌥⌘N, then a page, or a link from another app) and swipe back with
  two fingers over its page: Chromium's back arrow shows, and letting go closes the window, as ⌘[
  does. A page it went on to comes first; a Peek never closes this way. The
  `little-window-swipe-back` scenario asks the swipe's questions (`cra://debug?littleSwipeBack=`).
  The same swipe over the window's address bar does the same, and a swipe to the left there goes
  forward (`little-window-bar-swipe` feeds the bar trackpad events, `cra://debug?littleBarSwipe=`).
- **#12:** a two-finger swipe in the hidden sidebar (⌘S) switches spaces, and the next space
  draws mid-swipe. There is one link bubble only, and the dashed ring shows only on a
  cross-space keyboard switch.
- **#28:** the speaker sits between favicon and title, a click mutes, and it doesn't blink
  between tracks.
- **#47:** ⌘T highlights the New Tab row; the list scrolls only enough to show the active row.
- **#85, #543:** ⌘Return keeps the bar open; the "New Tab Created" toast shows only while the sidebar
  is hidden, for a ⌘-clicked, middle-clicked or Open Link in New Tab link too.
- **#92:** in a Little Window, ⌃⌘2 sends the page to the window already on space 2.
- **#174:** with a page text field focused, ⌘Space switches input source and ⌘` switches
  windows.
- **#194:** in Google Docs, ⇧⌘C copies the URL instead of opening Word count; DevTools still
  gets ⇧⌘C.
- **#192:** in a page's rich text field, ⇧⌘V pastes plain text and Edit ▸ Paste and Match Style
  is enabled.
- **#33:** hover the player stack: check the volume slider, the Picture in Picture button, and
  the light card in a light space.
- **#382:** rest the pointer where ⌘T's third row will appear and press ⌘T without touching the
  mouse: the top row stays selected (Return opens it); type, and the rows that change under the
  still pointer leave the top row selected too; move the pointer a little and the row under it
  takes the selection. HoverGateTests pins the rule; this checks AppKit's events on a real screen.

### Peek, Little Window, Picture in Picture, split view, Capture

- **#741:** with a video in Picture in Picture and another app in front, pinch over the window: nothing happens, as in
  Arc (macOS gives a pinch only to the app in front). Click the window once: Cra comes forward (its menu bar), no
  browser window shows even for a moment, and a pinch now resizes it, again and again. The other app's windows stay
  in front of Cra's browser window. Do it once from another app's full-screen Space too (#206): you stay on that Space.
  (`pip-pinch-background` checks the click's decision in a test copy, which never comes forward.)
- **#373:** with Settings ▸ Links ▸ "⌥⌘-click opens a Little Window" on (it is off by default), hold ⌥ and ⌘ and
  click a link on a page with the pointer: the link opens in a Little Window and the page stays where it is, from
  a normal tab, a pinned tab, a target=_blank link and a WebKit tab (a DRM site, whose page gets no posted click). With the switch off, ⌥⌘-click opens Split View (#298);
  with ⇧ or ⌃ down as well, it is another click. (`option-command-click-little-window` posts the click through
  the app's event queue; a click from the hardware, with the keys held on the keyboard, is this line.)
- **#435:** with Settings ▸ Links ▸ "Hide the Little Window toolbar until you need it" on, open a Little Window
  over another app and rest the pointer at its top edge: the bar and the traffic lights slide in over the page,
  which doesn't move; move down past the bar and they go. Open "Open in"'s list and the command bar from the bar:
  it stays out while they are open. (`little-window-toolbar-auto-hide` checks the layout, the strip and the keep
  zone through `cra://debug`; the real pointer's events over the page's view are this line.)
- **#493:** with Settings ▸ Links ▸ "Hide the Peek toolbar until you need it" on, Shift-click a link: the Peek's
  page fills the card. Rest the pointer at the card's top edge: its bar slides in over the page, which doesn't move;
  move down past the bar and it goes. ⌘L opens the address with the bar away, and ✕, Expand and Add to Split beside
  the card still work. (`peek-toolbar-auto-hide` checks the layout, the strip and the keep zone through
  `cra://debug`; the real pointer's events over the card are this line.)
- **#520:** open Gmail in a Peek (Shift-click a mail.google.com link, signed in) and press Escape: Close turns
  into the red Confirm pill, and a second Escape closes the Peek. A quick double Escape closes it at once. Then a
  plain site (github.com) in a Peek: one Escape closes it. (`peek-escape-closes` and `peek-escape-page-uses-it`
  stand in for Gmail with a page that cancels Escape; Gmail's own key handling, which can change, is this line.)
- **#381:** click a link to another site in a favorite, next to Arc doing the same: the peeked page's
  favicon springs onto the tile's top right corner on a white square (black in a dark space), 4 pt
  past the corner, with a soft shadow, and springs off when the Peek closes. Check a split favorite
  too. (`favorite-peek-badge` checks the frame and that nothing clips it; Arc's values come from its
  code, so the side-by-side with Arc and the spring's feel are this line.)
- **PR #221:** opening a Peek fades the page behind and draws it back a little, its margins widening
  while the sidebar stays still, and closing brings it back in one smooth motion with no jump at the
  end. With "Pages fill the window edge to edge" on, the page only fades. (The values are checked
  by the peek-backdrop scenario; this is the motion.)
- **#195:** in a Peek and a Little Window, click in the page, then Back, Forward, Refresh, the
  address and "Open in": each works on the first click. Capture and scroll: the page moves and
  the grey picture and the lens follow. With another app full screen, ⌥⌘N opens a Little
  Window over it, and doesn't when Settings ▸ Links ▸ "Open Little Window when I press ⌥⌘N in any app" is off.
- **#585:** signed in to Netflix (it plays in WebKit, docs/protected-media.md), play a film and choose
  View ▸ Picture in Picture: the film opens in the system's Picture in Picture window, and choosing it
  again puts it back. Switch tabs while it plays: it opens by itself, and comes home when you go back; press the
  window's ↖ instead and Cra switches to Netflix's tab, where the film plays on (the button is PIPAgent's, which a
  scenario can't press); ✕ pauses it without switching. Netflix's
  player makes its video with `disablePictureInPicture`; the `webkit-pip-opted-out` scenario covers such
  a video on a fixture, this checks the real player and its FairPlay video.
- **#357:** play an embedded YouTube video aloud on a blog (the player in an iframe), switch tabs:
  it goes into Picture in Picture. A background test copy can't hand the iframe its key press,
  before or after #357; the pip-leave-tab scenario covers a player in the page itself.
- **#357:** on crabrowser.app/folder with a 4-tab folder, Open All opens one tab and the toolbar's
  crossed-out windows button (or "Pop-ups Blocked" under the sidebar's address) shows; its menu
  opens the rest, and Always Allow Pop-ups from crabrowser.app lets the next Open All open all.
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
- **#354:** on two displays, with another app full screen on the primary one and Cra on the
  other: a link that opens a tab, a ⌘-click that opens one behind, a tab whose page has to load,
  a Peek and DevTools all leave the primary display on its full-screen Space.
- **#774:** the same two displays: a click on a link that downloads (with and without Ask Where to
  Save), a page's file picker and an alert leave the primary display on its full-screen Space,
  and only Cra's download flight shows, no arrow of Chromium's.
- **#231:** with Keep Cra in the menu bar on, the C shows in the menu bar in light and dark.
  ⌘Q takes the windows and the Dock icon away, and focus goes to the app behind. A full-screen
  window leaves its Space first. ⌥⌘N from another app opens a Little Window at once, with the
  Dock icon. Closing it takes the icon away again. New Window in the item's menu brings the
  windows back, and Quit Cra there quits.
- **#319:** with a custom app icon and Keep Cra in the menu bar on, ⌘Q, then New Window from the
  item's menu: ⌘-Tab and the Dock show the custom icon, not Segments
  (app-icon-dock-return.scenario only sees that Cra set it again). Then download a file: during
  and after the download, ⌘-Tab and the Dock still show the custom icon, with Chromium's progress
  badge on it while it runs (app-icon-download.scenario reads what Cra draws, not what the Dock shows).
- **#298:** in a tab on a DRM service (it opens in WebKit, docs/protected-media.md), Option-click a
  link: it opens as a split pane beside the page, as it does in any other tab (that scenario's
  posted click never reaches a WebKit page behind other windows).
- **Fandango at Home** (docs/protected-media.md; a mixed site whose player is a frame, which
  widevine-in-a-frame.scenario and protected-video-prompt.scenario show on fixtures, not the site):
  signed in to athome.fandango.com in Chromium, play a film you own. The toast offers Safari's
  engine with Once and Always. Once: the play page opens in WebKit signed in and the film plays,
  with no reloading. Back on the film's details page the tab is Chromium's again.
- **Protected videos on YouTube** (docs/protected-media.md; it takes an account that owns a
  film, which protected-video-prompt.scenario's fixture can't stand in for): signed in to YouTube
  in Chromium, open a bought film. The toast offers Safari's engine with Once and Always. Once: the
  page opens in WebKit signed in with only `youtube.com`'s cookies copied (cra.log: "copies N cookies
  of youtube.com"; Google's stay in Chromium), the film goes on from where it was, and its quality menu offers
  more than 480p. An ordinary video opened in that tab is Chromium's again, extensions and all.
  The Chromium session is still signed in afterwards.
- **Widevine that fails** (docs/protected-media.md; it takes an account, which widevine-fails.scenario's Clear Key
  fixture can't stand in for): signed in in Chromium to a DRM service that isn't listed (Viaplay, Zattoo or RTL+),
  play a film. Within seconds the tab opens again in WebKit, signed in (cra.log: "Widevine failed on <site>: moves the
  site to Safari's engine", then "copies N cookies"), "<site> plays with Safari's engine" shows, and the film plays.
  The Site Control Center's switch off takes it back to Chromium, and playing there again leaves it there. Shaka
  Player's Widevine demo (shaka-player-demo.appspot.com), which plays in Chromium, doesn't move.
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
- **#516:** on a trackpad, swipe the PiP with two fingers hard into each edge of the screen, into
  the menu bar and into the Dock, and keep pushing before you lift. The window stops with the hidden
  pointer still on it, then flies into a corner on the lift, and the pointer shows again there.
  The CraCore test covers where it stops; only real fingers show that the lift still reaches it.
- **#534:** on a trackpad, pinch the PiP open and closed, with Cra in front and with another app in
  front: it follows the fingers smoothly in the video's shape, stops where an edge drag does at its
  smallest and at the screen's edges, a window in a corner grows out of it, and a two-finger swipe
  still throws it. Next to Arc's, check where it grows from. **#573:** rest two fingers on the
  trackpad first, then pinch: it resizes as well, with Cra in front and with another app in
  front, and `pip: pinched` shows in cra.log. The overlay harness and the scenario hand AppKit the
  events in an order a trackpad can send (scroll and magnify that may begin, the pinch, the
  scroll's cancel at the lift) and the magnify through the app's event monitor; synthetic gestures
  posted through the window server didn't reach a background app at all, so only real fingers show
  that a trackpad's do.
- **#246:** a YouTube video's PiP shows no Chrome strip (site icon, host, dark top band) at any
  point, also in the first seconds; with the pointer away it is the bare video. On hover: Back to
  Tab on the left (with its words from 400 pt wide), the host centred and whole, Close on the
  right, one even dim layer.
- **#460:** a YouTube PiP opened from the player's button and by leaving the tab: hover it, click
  it, press keys while it is in front, swipe it, switch apps and Spaces. Only Arc's controls ever
  show, never Chrome's (Back to Tab, ±10 s, progress bar, captions) under them. If they do, cra.log
  has a "pip: Chromium's window got event type N, dropped" or "became key" line saying how.
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
- **#723:** open the Site Control Center in dark and in light appearance. Its arrow has the panel's
  colour, with no seam where they meet, and the popover's rounded corners show no square fill behind them.

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
- With Cra in native full screen and Bitwarden locked, open its separate vault-unlock window:
  it appears over Cra on the same macOS Space, accepts the password and closes normally without
  switching to a desktop. Compare with Arc; also check windowed Cra and a second display.
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
  A right-click or ⌃-click on the toolbar's ↻ shows the same menu, outside developer mode too
  (#517); a plain click still reloads. In a split, a right-click on the other pane's ↻ focuses that
  pane and Clear Cookies and Refresh reloads that pane, not the one that had the focus.
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
- **#705:** signed in to discord.com and web.whatsapp.com in sidebar tabs, close each with ⌘W, open it again
  (and once with ⇧⌘T): still signed in. Discord takes its token out of storage while it thinks DevTools are open,
  which Cra's sidebar makes it think, and puts it back as the tab closes (`site-saves-on-close` pins the mechanism).
- **#167:** on a Mac whose first language is Simplified Chinese, cra.log says `chromium locale:
  zh-CN` and chrome://version shows `--lang=zh-CN`.
- **#133:** pick Google in Settings ▸ Privacy ▸ Secure DNS. Without a relaunch, cra.log says
  `secure dns: secure via dns.google` and chrome://settings/security shows the same choice.
- **#190:** with Ask Where to Save Each File on, the save panel is a sheet on Cra's window, and
  Cancel cancels the download.
- **#574:** what a page shows over itself needs a real site or macOS's own prompts, so the
  scenarios (`page-dialogs`, `page-dialog-sign-in`, …) can't reach these: on meet.google.com,
  Present now shows Chrome's picker over the page (after macOS's Screen Recording prompt the first
  time), and Cancel ends it; on webauthn.io, Register shows Chrome's passkey dialog over the page,
  then Touch ID; a site that asks for a client certificate shows the certificate picker over the page.
- **Web features without a scenario** (docs/web-features.md: macOS's own prompts or a real site; each
  line names its row in Tests/web-features.tsv):
  - web feature: screen share picker. On meet.google.com, Present now ▸ A window shows the picker over
    the page and shares the window picked; Stop sharing ends it.
  - web feature: passkey with Touch ID. On webauthn.io, Register and then Authenticate each show the
    passkey sheet over the page and take Touch ID.
  - web feature: client certificate. On a site that asks for one (badssl.com's client certificate
    page), the certificate picker shows over the page, and Cancel shows the site's error.
  - web feature: Bluetooth chooser. On a Web Bluetooth demo (googlechrome.github.io/samples/web-bluetooth),
    Scan asks macOS for Bluetooth the first time, then shows Chrome's chooser on Cra's window; Cancel
    tells the page no device was picked.
  - Keyboard lock: on a page that goes full screen and locks the keyboard (keyboard-lock.glitch.me, or Chrome
    Remote Desktop's full screen), a press of Esc stays with the page, and holding Esc for two seconds leaves full
    screen. (`page-fullscreen-keyboard-lock` presses it; a scenario can't hold a key.)
  - web feature: SaveFrame. Open a PDF (any link to one) and press the viewer's Save button: the file
    saves as a download (or into the save panel with Ask Where to Save Each File on) and shows in the bin.
  - Download a PDF and an image, open the downloads tray at the sidebar's bottom left and drag each row
    onto the tab list: the insertion line shows, and let go it opens as a tab there (the PDF in the PDF
    viewer), behind the page you're on, as in Arc. A .zip dragged the same way is refused. (`drop-file`
    drops them through `cra://debug`; a scenario can't drive a real drag.)
- **#272:** download a large file. The bin over the Library button keeps a ring that fills as it
  downloads; right-clicking its row in the tray and on Library ▸ Downloads offers Pause Download and
  Cancel Download, and a paused row reads "Paused". ⌘Q while it runs asks "Downloads in progress";
  Keep browsing keeps it going. Once it finishes, a check replaces the arrow, and its row's menu
  reads Open / Copy <kind>, Show in Finder, Hide from Cra and Move to Trash.
- **Screenshots in the downloads list:** on a Mac whose screenshots go to the Desktop (the default)
  and where Cra hasn't been allowed the Desktop yet: launching asks nothing. Open the Library once:
  macOS asks for Desktop access; allow it. Press ⇧⌘4 and take a screenshot: within a few seconds it is
  the newest row when you hover the Library button, with its picture, and drags onto a page's upload
  field. Unticking Screenshots in the Media button's "Show media" menu takes it out.
  (`downloads-tray-screenshots` covers a screenshot in ~/Pictures; macOS's question needs a person.)
- **PR #254:** with the release app as the default browser, open a page in Safari on an iPhone
  signed in to the same Apple Account and click the Handoff icon in the Dock. The page opens in
  Cra, in the space Air Traffic Control picks, and not in Safari.
- **#753, dialog corners on macOS 15:** on a Mac with macOS 15, press ⌘Q (with Ask before quitting on) and open
  New Profile. No white shows in the dialog's corners: the dark card rounds with the sheet. On macOS 26 they
  keep Arc's rounder corners. `DialogCornerTests` pins the radius; only macOS 15's own sheet shows the fit.
- **#745, Handoff to the iPhone:** with the release app in front on a web page, swipe up to the app
  switcher on an iPhone signed in to the same Apple Account. A Handoff suggestion at the bottom opens
  that page in the iPhone's default browser. Another tab's page replaces it; an incognito window or a
  chrome:// page offers none. `handoff-offers-page` pins what Cra offers; only a phone shows it arrives.
- **#261, #195:** with Stage Manager on, use Cra full screen with 20 or more visited tabs for ten
  minutes. No grey pane flashes and Stage Manager shows no window coming and going. After a
  minute pass, the GPU helper's footprint (`footprint -p <pid>`) still drops as the hidden tabs
  let go of their tiles (#195: 20 tabs, 386 → about 235 MB).
- **#308:** in full screen, drag the toolbar, the sidebar's top strip and the page's margin by
  hand. The window stays put. With the sidebar hidden, the pointer at the top of the screen
  reveals the title bar with the traffic lights in it. The `fullscreen-window-chrome` scenario
  checks the window's flags; only a hand drag shows that AppKit honours them.
- **Blocked requests:** with Block Ads & Trackers on, ziplyfiber.com, fidelity.com and
  allstate.com show their pages. They stayed white while a blocked request was cancelled instead of
  failed: Adobe Target hides the page until its request ends. (The scenario checks the failure and
  that the blocked host is never asked; this needs the real sites.)
- **Install count:** within an hour of the release going live, Phantom's "Cra installs" site
  (phantom.kildahl.dk) shows check-ins from the new version under Version, and from Intel too under
  Chip once Intel Macs have updated. None means released copies aren't checking in (docs/sharing.md,
  "Install count"); the `install-checkin` scenario only proves a test copy does.

### Sync

- **PR #289:** with a signed build on two Macs and Sync with iCloud on, a tab opened on one Mac
  shows on the other within about a minute, and back, five times in a row. Settings ▸ General
  shows "Synced" on both and never asks which sidebar to keep after the first answer. Needs
  real iCloud: the harness only stands in for a file that is still downloading.
- **PR #289:** the same with a folder in Dropbox, OneDrive or a similar service instead of iCloud.
- **Easels in sync:** with a signed build on two Macs and Sync with iCloud on, an easel with a
  few pictures and captures made on one Mac opens on the other with every picture, within about
  a minute; a title changed on each Mac shows on both; deleting it in Library ▸ Easels removes it
  on the other Mac and closes its tab there. Needs real iCloud: the harness doesn't download
  pictures in a subfolder file by file.

### iPhone

- **#866, the open iPhone Duo:** on a TestFlight build on an iPhone Duo (or the Duo simulator, which needs Xcode 27),
  unfolded: App Settings from the tab switcher's gear opens at full height; the bottom bar's tab and menu buttons sit
  within 540 pt in the middle; the onboarding Next button and the Spaces sync intro's buttons are no wider than 540 pt;
  the tab switcher shows a phone-sized card in the middle with its neighbours. Folded, everything is as on an iPhone.
- **#504:** on a TestFlight build with the default-browser entitlement, Settings ▸ Set Cra as
  Default Browser opens Cra's page in iOS Settings with a "Default Browser App" row; picking Cra
  there makes a link tapped in Messages open in Cra. Settings ▸ Apps ▸ Default Apps ▸ Browser App
  lists Cra too. Needs a real iPhone and Apple's signing: the policy test only sees the file.

- **Opening the search sheet (`MobileSearchMotion`):** on a real iPhone in dark mode beside Arc Search, over a
  page: tap the pill. The sheet moves on the frame after the finger lifts, solid from the start, the plus at the
  field's left with "Search..." to its right, and the mic and eyes fade in with the field as it opens (the new tab drawer's `drawerAccessorySpan`; the page menu's address editor keeps Arc Search's second half). Needs a human eye:
  the simulator's frame timing is not the phone's.

- **The new tab drawer's field growing out of the pill:** on a real iPhone over a light page and a dark
  one, tap the pill, and pull it up and let go. The field's white lift grows with the field, its ends
  rounded all the way: no square corners inside the rounded edge. The lift was a bare layer on Core
  Animation's own timing and lagged behind the field; a UI test cannot catch a frame mid-move. After a search, open it
  again: the mic and the mask only fade in with the field, without springing up from small, which
  they did when the sheet still remembered the clear button.

- **#675:** on a TestFlight build on a real iPhone with System Haptics on, press the New Tab pill, the
  tab stack and the up arrow: one very subtle tick as the finger comes down and nothing as it lets go. In
  the page menu, tapping the address gives the same subtle tick; the tiles and rows a light one, Pin and
  Summarize also on release, and the capsule only on release. Nothing with System Haptics off. The
  simulator plays no haptics; `BarHapticsTests` and `MenuHapticsTests` only count them.

- **The pill's press:** on a real iPhone beside Arc Search, tap the New Tab pill quickly, then press and
  hold it: it presses in under the finger (94 %, Arc Search's about 94.5 %) and comes back out without
  growing past its size (it puffed up to 106 %). `PillPressTests` covers a held press; a quick tap's way
  back needs an eye.

- **The swipe across the page (`MobilePageSwipe`):** on a TestFlight build on a real iPhone with System
  Haptics on, beside Arc Search. Tap a link, then drag the page right slowly: it holds back, a quarter of the
  finger's way, then lets go with one tick about 75 pt in and catches up; the page it goes back to is under it,
  a third of the way along, with a soft shadow on the page's edge, and nothing jumps when its picture gives way
  to the live page. On a tab's first page the hold is harder: still for the first 16 pt, an eighth of the
  finger's way after, the tick about 185 pt in, and from it the page shrinks into a card while the tab before
  it lifts off the tab button's front card and flies in beside it. Let go before the tick, both go back; after
  it, the tab closes and the next page shows without a black frame. Everything moves at 120 Hz, the cards'
  flight included, and the release never stutters. `PageGestureTests` pins the geometry, the hold and where it
  lets go; the tick, the frame rate and the feel need a phone.

- **The bar's settle:** on a TestFlight build on a real iPhone, flick the page up and down quickly,
  each flick landing while the bar is still moving, and flick from near the bottom where the
  home-indicator swipe can take the touch: the bar always comes to rest fully open or closed, never
  between them. The simulator cannot stage a system gesture taking the page's pan;
  `testFlicksLandingOnASettleLeaveTheBarAtAnEnd` covers the flicks themselves.

- **The tab row's settle (PR #882):** on a real iPhone with five or more tabs, flick the tab row and
  take a card up before the row lands: the row holds still under the held
  card, then settles on the card it was heading to once the card is let go or thrown away, also when
  a card thrown just before lands meanwhile (`aHeldRowResumesOnItsCardAfterAnEarlierThrowLands`). Catch the
  row with a finger while it springs back from past either end: it stays under the finger. Throw a card
  up and flick the row before it has flown off: the row lands on the card the flick was heading for
  (`aFlickStillLandsOnItsCardWhenAnEarlierThrowLeaves`). XCUITest
  waits for the row to rest before its next gesture, so it can't stage any of these;
  `catchingTheRowPastAnEndHoldsItWhereItIs` covers the catch's arithmetic.

- **The page under the bar (iOS 26):** on a TestFlight build on a real iPhone, open a long page with
  a sticky or fixed `bottom: 0` element and drag the bar slowly both ways, then let it settle: the
  element rides on the bar's top every frame, never under it and never apart from it, the page's
  scroll stays even under the finger the whole way, the page's content shows through the bar's
  frosted material, and the last line scrolls clear of the bar.
  `PageUnderBarTests` pins the geometry in the simulator; the blur and the frame rate are a phone's
  to judge. Then open a workbook in Excel for the web, signed in, on an iPhone and an iPad: the
  sheet tabs and the status bar under them sit on the bar's top, all tappable; the simulator has no
  signed-in Office account, so `testAScreenSizedAppKeepsItsBottomStripAboveTheBar` stands in with a
  `100vh` page.

- **Pull to refresh:** on a TestFlight build on a real iPhone with System Haptics on, pull a page down
  from its top: the page's whole view comes down with the pull (its content stays at the top inside it, so
  the page does not scroll) and the coloured band behind the status bar grows edge to edge to meet it, its
  bottom staying on the page's visible top; letting go springs the page back. The reload ring sits in the
  band, filling clockwise from the top in the status bar's ink (white or dark grey), clear at its tail with
  the end ink fading in to 90 % opaque, and only the tip rounded; at the 128 pt line a solid second lap
  springs out over its seam, further and bouncier the faster the pull (a slow pull barely nudges it).
  Ticks start at 24 pt, one every 2 pt, faint and strengthening, and the strongest lands on that line as
  a heavier tick; pushing the pull back up ticks down through them again, and past the line the pull can
  go further in silence. Pushing it back past the top hands the drag to the page's scrolling, so it
  continues without lifting. Letting go plays one medium impact as the page reloads; on a full pull the
  solid second lap turns 108° in 0.3 s as it fades, and short of the line it unwinds back to the top. A
  short pull and one dragged back up before letting go are silent. Nothing with System Haptics off.
  `MobilePullHapticsTests` pins the sequence; `PullHapticsTests` counts the ticks and checks the band
  meets the page.

- **#536:** on a TestFlight build, sign in to a site with a passkey saved in iCloud Keychain and
  one saved in 1Password (webauthn.io works for both): iOS's passkey sheet comes up and the sign-in
  completes. The simulator only reaches the sheet (it has no Face ID enrolled or passkeys saved).

- **#570:** with the default settings, open `https://ww7.readopm.com/read-manga/` and
  `https://ww13.readonepiece.com/` and wait half a minute on each: no "Anna has sent (7) photos",
  "The file is ready to download" or "Something Amazing Awaits!" overlay, tapping the page opens no
  ad tab, and the page menu counts what was scrubbed. "Reload without ad blockers" brings the ads
  back. Needs the real sites (their ad hosts change every few days) and a network that doesn't
  filter them: the Mac this was built on resolves both to a DNS sinkhole. CraCore's FilterListTests
  and the UI test `testAnAdLoaderFromAnUnlistedDomainIsStoppedByItsPath` pin the rules themselves.

- **#570, added lists:** on a real iPhone, add `https://easylist.to/easylist/easylist.txt` under
  Default Site Settings ▸ Block Lists. Its row says "N rules · M rules Cra can’t use" within a few
  seconds of the fetch, the next page load has its rules (a news site loses its ad slots), and a
  relaunch opens the first page without a wait (the compiled lists are looked up, not compiled
  again). Needs a phone for WebKit's compile time and the real list: CraCore's
  `AddedListRulesTests` compile a list of EasyList's shape on the Mac, and
  `testAnAddedListsPathRuleStopsAScriptFromAnUnlistedDomain` pins a served list in the simulator.

- **PR #827, the filter helper's new permissions on an existing profile:** update a Mac from the previous
  release, with EasyList (or any list with network rules) on in Settings ▸ Privacy ▸ Block lists. After
  the update, chrome://extensions in that profile shows no disabled helper and no permission prompt,
  and a page from a blocked ad host still fails to load. The helper (1.2) asks for scripting and site
  access; Chrome grants an unpacked extension's new permissions as it loads, but only an update from
  a real older profile shows that. The scenarios start from a fresh profile.

- **#623, the pull-up's motion:** on a real iPhone at 60 fps, record a drag up from the + pill let go
  halfway and compare it frame by frame with the reporter's Arc Search recording
  (streamable.com/vbu4dx): let go, the sheet stays put until the keyboard comes, then rises with it
  and rests about 0.28 s after letting go, with no sink towards the bar and no overshoot. The
  simulator records at a variable rate, so only a phone settles the timing; CraCore's
  `aLetGoSheetWaitsForTheKeyboardWhereItWasLeft` pins the hold.

- **Closing the search sheet:** on a real iPhone beside Arc Search, open the sheet over a page and tap
  above it: the field rides down on the keyboard into the + pill, and the bar's buttons come back as it
  lands (`MobileSearchSheet.Settling`; the sheet vanished on the close's first frame).

- **#572, the address turning editable:** on a real iPhone, tap the address in the page menu: the
  menu does not visibly close first. The editable field takes the capsule's place in the same
  panel and the keyboard lifts it from there, and the page behind does not zoom out or move: only
  the + button's search pushes it back, and dragging this panel down leaves the page still. The
  simulator records animations at a variable rate, so
  only a phone settles the handoff; `testTheMenusAddressIsEditedInThisTab` pins the end state.

- **Escape closes the search sheet:** on a real iPad with a hardware keyboard, press ⌘T over a page,
  then Escape: the sheet closes and the page stays as it was; Escape on a page with the sheet down
  still reaches the page (a site's own dialog closes). XCTest never delivers Escape to the app in the
  simulator; `MobileKeyCommandsTests.escapeIsThePagesUnlessTheSheetIsUp` pins when it is claimed, and
  `KeyCommandTests` pins ⌘T and ⌘L. On an iPad on iPadOS 26, ⌘T and ⌘L open the search too, also with
  nothing in focus (no tap on the page since it loaded) and on the empty home, and neither opens anything
  under a summary: XCTest on iOS 26 drops ⌘ more often than not, so `KeyCommandTests` runs from iOS 27.

- **A choice in the search sheet (`MobileSheetLeave`):** on a real iPhone in dark mode beside Arc Search, with
  google.com's dark theme on, search for google.com from a page and from the empty home screen. The sheet rises and
  fades, the screen goes black without lightening on the way (the band under the Dynamic Island included), and the
  page appears without a white frame. `testAPageOpenedFromTheSheetIsCoveredUntilItHasDrawn` checks the page and the
  band are out of sight under the cover; the timing needs a human eye.

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
