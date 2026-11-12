# Developing Cra

Notes for working on the code. How to send a change is in
[CONTRIBUTING.md](../CONTRIBUTING.md); user-facing docs live in the help centre at
[crabrowser.app/help](https://crabrowser.app/help).

## Build

    scripts/build.sh          # fetches CEF on first run, builds build/Cra.app
    scripts/build.sh debug    # debug build
    scripts/run.sh            # build if needed, then open; --rebuild [debug] forces a build
    scripts/dev.sh            # dev loop: debug CraDev.app, rebuilds + relaunches on save (~4 s)
    scripts/dev.sh --once     # build and launch CraDev.app once, logs in this terminal

`just` lists all of the scripts below with what each does (`brew install just`; the
[justfile](../justfile) is one recipe per script). A recipe passes its arguments on, so
`just build debug` runs `scripts/build.sh debug`. CI calls the scripts directly, and so can
you.

Requirements: macOS 14+ on Apple silicon, Xcode 16+, CMake (`brew install cmake`), about
1 GB of disk for CEF and the build products. `CRA_ARCH=x86_64 scripts/build.sh` cross-compiles the
Intel app into `build/x86_64/Cra.app` (another ~1 GB); every release ships both.

`scripts/fetch-cef.sh` pins the CEF version and downloads it into `vendor/cef` (not
committed). It fetches Cra's own CEF build, made by `scripts/build-cef.sh` with H.264/AAC
and the patches in `scripts/cef-patches` and published as a `cef-*` release by
`scripts/publish-cef.sh`; `CEF_URL` points it at Spotify's stock build instead. A daily workflow (`.github/workflows/cef-updates.yml`) opens an
issue when a newer stable CEF is out; `scripts/update-cef.sh` moves the pin.
If the release download fails, `scripts/download-cef.py` retrieves the same Cra asset
through GitHub's public API and verifies its published SHA-256 before unpacking.
Custom `CEF_URL` downloads never fall back to a different Cra build.

## Layout

- `Sources/Cra` — the app: `App` (delegate, key bindings), `Services` (sidebar store,
  persistence, import, updates, extensions, live folders), `UI` (sidebar, command bar, split
  view, windows, settings, onboarding)
- `Sources/CraCEF` — Objective-C++ bridge between Swift and CEF
- `Sources/CraHelper` — Chromium subprocess executable
- `Sources/Cra/Services/WebKit` — the WebKit page that DRM services open in
  ([protected-media.md](protected-media.md))
- `Packages/CraCore` — models and decisions with no AppKit or Chromium (the sidebar model,
  settings and the other data-folder files, Air Traffic Control, live folder data, key chords,
  space themes, Arc theme import, the favorites grid), visible in every `Sources/Cra` file.
  The layer rules are in [CLAUDE.md](../CLAUDE.md)
- `Tests/` — the harnesses that compile production files against fakes, and the smoke test
- `resources/` — app icon, brand PNGs, the ad and tracker blocklist with its licence notices
- `scripts/` — build, release, CEF and test tooling; `scripts/clips` records release clips
- `docs/arc-reverse-engineering.md` — what was learned from Arc and how
- `docs/release.md` — signing, notarization and the release workflow
- `vendor/cef` — CEF binary distribution (fetched, not committed)

Data lives in `~/Library/Application Support/Cra`: the sidebar and archive as JSON,
`keybindings.json`, each tab's back and forward list in `PageHistory/`, cached favicons, the logs
and a Chromium profile folder. Delete it to
start over.

Settings ▸ General ▸ Sync keeps `sidebar.json`, `settings.json` (minus each Mac's own fields,
`AppSettings.forSync`) and `keybindings.json` the same on the user's Macs, through iCloud
(`Documents/Cra` in the app's iCloud Documents container; docs/release.md says how the signed
build gets the entitlement) or through a folder a file provider syncs: `SettingsSyncService`
writes them with a `manifest.json` into a `Cra` folder there and applies a newer bundle another
Mac wrote (`SettingsSync` in CraCore decides). A file still downloading is waited for; files
from different writes (hashes that don't match the manifest, #378) are waited for one to two
minutes (`SyncMixWait`), then the Mac writes a whole bundle again; a file the manifest names that
is gone with no placeholder is put right the same way, after one minute on the Mac that wrote the
manifest and ten on another. A Mac that hasn't synced in the folder yet never writes over another
Mac's bundle: it waits for that Mac, then asks. A newer Cra's bundle is never written over. `cra://debug?sync=<label>` logs what the last look found. `sync.json` in the data
folder holds the location and the last bundle written or applied. To try it on one Mac, run a second instance on another
`CRA_DATA_DIR` with `CRA_SYNC_DEVICE=<name>` (a Mac is known in the folder by a hash of its
hardware UUID, which two instances share);
`CRA_SYNC_ICLOUD_DIR=<folder>` makes both treat that folder as the iCloud container.

`cra.log` is Cra's own log: each tab's page opening, showing, loading, failing to load (with
the net error and the extension that set the proxy) and closing, and three seconds after a tab
comes on screen and its page has loaded, what the page holds (`blank`, `visibility`, element
and body child counts, `painted` for a first contentful paint, `frameRate` for the animation
frames it got in half a second, `video` for the first video's dropped/total frames) and where Cra put it (view size, `window=covered` when another
window hides it, `display=` the refresh rate of the display it is on). A visible page with
`frameRate=0` was never asked to draw; frames without `painted` never reached the screen. `chromium.log` holds Chromium's warnings,
failed page loads and crashed renderers. Each launch keeps the last one's as `*.previous.log`.
Logs name sites by host only. Help ▸ Export Diagnostics… zips both with the GPU report,
the displays and their refresh rates, whether Stage Manager is on, the on-screen pages' state, settings, extensions and the last week's crash reports, with
addresses cut to their host; `cra://debug?exportDiagnostics=<path>` does the same without
the save panel.

## Tests

    scripts/test.sh                  # everything below except the smoke test, in seconds
    scripts/test.sh core             # only Packages/CraCore
    scripts/test-folder-glyph.sh      # folder emblems: layer projection, colors and Retina resolution
    Tests/smoke-launch.sh            # launches build/Cra.app three times, about 30 s
    scripts/scenario.sh all          # user journeys in build/Cra.app, about 6 minutes
    scripts/scenario.sh sleep-tabs   # one of them (Tests/Scenarios/<name>.scenario)
    scripts/coverage.py              # line coverage, and the changed-lines gate against origin/main
    scripts/coverage.py --base <ref> # the same against another base (CI passes the PR's)
    scripts/fuzz.sh                  # mutated importer fixtures under AddressSanitizer
    scripts/mutate.py [word]         # mutation testing of the pure code, about an hour; a word limits it

[testing.md](testing.md) has the rules, the layers, the gates and how to write a scenario.

CI runs the same tests on every pull request and push to main (no CEF download), once, through
`scripts/coverage.py` plus `scripts/lint.py`, and the smoke test on the app it builds. A change
to Markdown or `docs/` alone runs nothing.

- `Packages/CraCore` (`swift test --package-path Packages/CraCore`): a package of its own, so
  its tests build without `vendor/cef`. Code that decides something without a window or a
  page belongs here, with a test: a layout rule, a mapping from Arc's or Chromium's files,
  a policy. Expected values for anything copied from Arc come from Arc's measurements in
  `docs/arc-reverse-engineering.md`; fixtures hold Arc's own JSON, trimmed to what is read.
  `Fixtures/Model` holds data-folder files, current and older shapes, each with what Cra
  saved after loading it (recorded before the model moved here, #51).
- `Tests/test-browser-manager.sh`, `scripts/test-floating-sidebar.sh`,
  `scripts/test-extension-popup-candidate.sh`, `scripts/test-extension-state.sh`: compile a
  few production files with `swiftc` against fakes (`Tests/BrowserManagerSupport` stands in
  for CraCEF and the rest of the app). When the manager calls something new from the app, add
  a stub to `AppServices.swift`.
- `scripts/test-store.sh`: the real `SidebarStore`, `AppComposition` and importers on a
  `ManualScheduler`, against the made-up Arc and Chromium profiles in `Tests/Fixtures`.
- `scripts/test-policies.sh`: the decisions pulled out of the window controllers
  (`ExtensionLaunch`, `DevToolsToggle`, `FeatureFlags`).
- `scripts/test-folder-glyph.sh`: the standalone folder component's real AppKit layers and image
  pixels: emblems follow the front panel's perspective, keep their colors and proportions, and
  update at 1x/Retina. No CEF or visible window; coverage uses the same harness as `scripts/test.sh`.
- `scripts/test-window-content-grabber.sh`: the page-top grabber on AppKit windows:
  clicks reach the page immediately, non-arrow cursors keep the gesture, native resize edges and rounded corners stay free,
  a child page's drag starts in its browser window's coordinates, and the page stays outside WindowServer's native drag region.
- `scripts/test-link-summary-share.sh`: 5-Second Previews' Copy as Image (`LinkSummaryShareImage`)
  against Arc's own copy of a card: size at 3x, the picture's inset, the dashed line's pattern and place,
  the footer colour.
- `scripts/test-link-summary-panel.sh`: 5-Second Previews' card window (`LinkSummaryPanel`) off screen with
  a stub service: the loading card, the answer growing in under the link, the small card above its link, closing.
- `scripts/test-emoji-label.sh`: a space's emoji label in the dock and the space header, drawn
  clipped to its frame as macOS 27 draws it: the emoji's whole picture shows, in the same place (#399).
- `scripts/test-music-notes.sh`: the production note sprites over fixed white and black backgrounds
  at 1x and 2x, checking light-theme contrast and the dark-theme tint without CEF or a visible window.
- `scripts/test-live-folder-plugins.sh`: the real `CraPluginHost` (sandboxed JavaScriptCore) and
  the bundled GitHub, GitLab and Jira providers in `resources/live-folder-plugins`, through
  `LiveFolderPluginProcess` with made-up session responses: permissions, timeouts, and each
  provider's parsing and sign-in cases (`Tests/LiveFolderProviderTests.swift`).
- `scripts/test-key-bindings.sh`: `KeyBindingRegistry`'s command list on a `keybindings.json` of its
  own: the live folder plugins' commands after New Folder, and shortcuts kept through a synced file,
  a reset and Reset All.
- `scripts/test-sidebar-creation-menu.sh`: the sidebar + menu's real window and view off screen:
  rows and keys, clicks on enabled and disabled rows, Arc's open and close timings, and the +
  turning into an × on its spring.
- `scripts/test-easel-canvas.sh`: the real `EaselSheetView` in an off-screen window, driven with
  synthetic mouse and key events: one click picks a text block, a double click edits it, Return and
  Escape end editing, Delete removes it, its size pill follows a drag. Undo and Redo, copy and
  paste, the object and canvas menus, the colour picker, a pasted address as a link card, the
  alignment guides and a live capture (through a fake `EaselLive`); every kind of item drawn into
  an sRGB bitmap and its pixels compared with Arc's colours. Then `EaselBrowser` against a stub
  `CraBrowser`: Peek's opaque canvas, the clear page and dark bar it reports to the tab that takes
  it over with ⤢, and the capture menu's New Easel and Send To… writing their easel files.
  `Tests/Scenarios/easel.scenario` checks the rest in the app: `cra://debug?easelLive=<s>` (a
  capture's live page draws onto its card), `easelLink=<url>` (a link card reads its page),
  `easelDraw=1` and `easelPick=<n>` (the picker and the object menu).
- `scripts/test-perf.sh`: the performance recorder on a real main run loop: injected stalls,
  hang files with a `sample` stack, the session marker, ownership, the recording switch
  ([performance.md](performance.md)).
- `python3 Tests/test_cef_download.py`: offline checks for direct downloads, API fallback,
  checksum and metadata failures, and custom URLs; included in `scripts/test.sh`.
- `scripts/lint.py`: Cra's own rules (testing.md), checked by `scripts/test.sh`.
- `Tests/smoke-launch.sh [app]`: starts the app on a throwaway data folder with no pages,
  with a page opened, then with it restored, and quits it like ⌘Q after a settings write.
  It fails on a crash, a hang, an error exit or a new crash report, which is how a `CHECK`
  inside Chromium shows up. Its own data folder lets it run next to your daily Cra.

What none of these see: compositing (the sidebar blur), fullscreen spaces, and how real sites
behave. Check those by hand, and say how in the PR.

Scenario hooks for a command file (`cra://debug?…`): `checkStore=1` logs a fault per broken
sidebar link, `pageJS=<js>` runs script in the focused page, `installExtension=<folder>` and
`removeExtension=<id>`, `extensionAction=<id>`, `sidePanelJS=<js>` (the value in the extension side panel's
page, to cra.log), `fullscreen=1|0`, `appActive=1|0` (the sidebar drawn as if
Cra were in front or behind, e.g. the download bin's dimming), `windowSize=1280x800`,
`snapshot=<ViewClass[,n]>&out=<png>`, `sleepTabs=<seconds>` (the 10 tabs used last too), `memoryPressure=warning|critical` (one
memory-pressure sweep at that level, if Settings ▸ Tabs has it on), `sleep=1` (what the Mac going to
sleep does: notes Chromium's audio service), `wake=1` (what waking the Mac does: the now-playing cards
re-read their tabs' sound, a tab-sleeping pass runs and cra.log says whether the audio service lived), `stall=<ms>` (blocks the main
thread), `perfReport=<path>` (the recorder's perf.json now), `systemAppearance=light|dark|system`
(the appearance Auto space themes follow, without changing the Mac's), `themeEditor=1` (Edit
Theme Color… for the focused space), `sidebarShown=<label>` (whether the window shows its sidebar,
and the View menu's Hide/Show Sidebar row: its title and the key it answers to, an App Shortcut's
when one names it), `relaunch=1`, `quit=1`, and `nowPlaying=state|toggle|next|previous|pip|dismiss` (the sidebar player's
newest card, then a `Cra nowPlaying[<label>] <host> playing=… prev=… next=… video=… pip=…` line per card
on stdout; `&label=` tells checks apart).

## Running a test instance

`scripts/dev.sh` builds a separate `CraDev.app`, including Sparkle, without a production
update feed or URL registrations. The script runs it on `build/dev-data` (set `CRA_DATA_DIR`
for another profile); opened directly from Finder, CraDev uses `~/Library/Application
Support/CraDev`, never the installed Cra's profile. Ad-hoc development builds use a mock
encryption key for fresh profiles; use test data and do not copy a daily browser profile
or real credentials into them.

The dev bundle records the CEF download source and Sparkle version. Changing either
pin refreshes the bundled frameworks, including an engine rebuild with the same CEF
version but a new release suffix. The watcher notices changes to both fetch scripts.
Compilation happens before the running dev instance stops; bundle replacement happens
only after it has quit. Quit any separately launched CraDev before starting another dev
script, so it cannot overwrite a framework still in use.

Cra is single-instance and the installed copy receives every `cra://` URL, so test a
build next to your daily Cra with its own data folder and a command file:

    CRA_DATA_DIR=/tmp/cra-test CRA_COMMAND_FILE=/tmp/cra-test.cmd build/Cra.app/Contents/MacOS/Cra &
    echo "cra://action/newTab" >> /tmp/cra-test.cmd

Every line appended to `CRA_COMMAND_FILE` is handled like a `cra://` URL, including the
scripting hosts below.

To measure smoothness, add `CRA_HITCH_LOG=/tmp/cra-hitch.log`: every main-thread stall of
8 ms or more is logged (`<seconds> stall <ms>`), with each command-file line as a
`mark` between them. The main thread is also Chromium's browser UI thread, so a stall
there delays input and scrolling too. Compare builds by running the same command
script against each.

`CRA_TEST_BACKGROUND=1` keeps a test instance behind whatever you are using: its windows
open at the back and it ignores every request to activate (Chromium's included). Launch it
with `open -g -n --env …` so macOS doesn't bring it forward either. Two command-file hooks
drive the sidebar without touching the pointer: `cra://debug?swipe=-14,22` plays a space
swipe (22 trackpad samples of 14 pt) and `cra://debug?scroll=30,30,150,700` scrolls the
scroll view at x 150, y 700 of the window (from its top left) 30 pt a frame for 30 frames.
Measure them with `sample <pid> 6 1` and compare the main thread's busy time between builds.

`CRA_TEST_SCREEN=<display>` opens every window of a test instance on that display instead of
the one you are using: `left`, `right`, `main` (the menu bar's) or a display's name as System
Settings ▸ Displays shows it (part of it is enough when only one display matches). Export it in
`~/.zshenv` and every launcher that runs the binary directly passes it on (`scenario.sh`,
`smoke-launch.sh`, `dev.sh`), so test copies started by agents stay on
one screen. Saved window frames keep their place relative to their display; `clip.sh` ignores it.
Unset, or naming no connected display, windows open as usual.

Tidy Tabs needs Apple Intelligence. `CRA_TIDY_FAKE_MODEL=1` stands in a model that groups by
site (after a 1.6 s pause), so a test instance on any Mac shows the button, the squiggle and the
groups, Tidy Tab Titles names a pinned tab after its title's first part and Tidy Downloads tidies a
download's file name by hand; `CRA_TIDY_FAKE_MODEL=off` (or `preparing`, `ineligible`) shows Settings ▸ Max as a Mac
without Apple Intelligence would. `cra://debug?tidy=1` runs Tidy on the window's space without
hovering the divider, `cra://debug?undoTidy=1` is ⌘Z's undo and `cra://debug?settingsPane=max`
opens Settings on a pane.

`cra://debug?dragEnd=<text>` ends a drag of the window's tab whose URL holds the text, let go
with nothing taking it, the way a drag out of the sidebar ends: outside every Cra window it opens
in a new Blank Window (`&at=x,y` picks the point, from the screen's top left).
`cra://debug?blankMoveTo=<n>` picks the nth space in the Blank Window's "Move to…".
`cra://debug?browserWindows=<label>` logs each browser window's kind (normal, blank, incognito),
space, tabs, open tab and frame; cra.log gets the kinds and counts only.

`cra://debug?menuAt=315,24` opens the menu a click at that window point would open (the
developer-mode ⌄ here), and `&button=right` the context menu, a tab row's for instance.
`&target=little` aims at the newest Little Window instead (its profile chip, for one).
Posted mouse events don't reach Cra's views and the rows have no AX menu action, so this is
the way to check a menu without the pointer. The menu shows up on screen. While it's open,
it is an AXMenu child of the app: each item's `AXMenuItemCmdChar`, `AXMenuItemCmdModifiers`
and `AXMenuItemMarkChar` give its shortcut and checkmark, and AXCancel closes it (a posted
Esc doesn't). The first menu after a launch can close before AX sees it, so open it again.

The sidebar's tab list and space pager are AppKit (`UI/Sidebar/List`): rows are plain
layer-backed views rebuilt from the store when it changes, a swipe moves the pager's layers
and the window tint (`PagedGradientView`) in Core Animation, and SwiftUI keeps the favorites,
space header, top bar and dock.

Pages are embedded in their pane cards (`EmbeddedPages.swift`): Chromium's page views move
from their Chrome window into the card, like Arc and Dia, and the Chrome window stays behind
empty, click-through and never key. Pages go back into their window while DevTools is open.
`CRA_EMBED_PAGES=0` (or `defaults write dk.kildahl.cra embedPages -bool NO`) keeps pages in
their own child windows, the hosting before 0.1.17, for comparing the two.

DevTools are a Chromium window too, made 10 pt square in a corner of the screen. Whoever owns
the page hangs it over the page's area and lays the page's window over the room the docked
frontend leaves (`DevToolsPlaceholder` in CraCore, `DevToolsWindowChrome`): `MainWindowController`
for a pane, `LittleWindowController` for a Little Window and a Peek (#348).
`cra://debug?inspectAt=x,y` is Inspect in the page's right-click menu (`&target=little` for the
newest Little Window or Peek) and `cra://debug?devToolsShown=<label>` logs where each Little
Window's DevTools are.

### Cleaning up after test copies

A renamed test copy leaves files outside its own folder: a 300 MB–1 GB code sign clone in
the per-user temp folder when it's killed instead of quit, plus caches, preferences and
LaunchServices entries under its bundle id. Dozens of them filled a 460 GB disk. Give a
copy a bundle id starting with `dk.kildahl.cra.test.` (or another `dk.kildahl.cra`,
`dk.kildahl.test.`, `app.crabrowser.` or `dev.cra.` id), quit it through its menu rather
than killing it, and delete it when you're done.

`scripts/clean-test-leftovers.sh` removes what's left: clones no process has open, the data
of test bundle ids that aren't running, Claude Code scratchpads of this repo that haven't
changed for a day, and LaunchServices entries of deleted Cra bundles. It never touches
the installed Cra's ids, CraClip, a running app or anything changed in the last hour. Use
`--dry-run` to see what it would do. In Claude Code it runs in the background at most every
30 minutes as a Stop hook (`.claude/settings.json`), and the log of the last run is
`$(getconf DARWIN_USER_TEMP_DIR)cra-clean-test-leftovers.log`.

## Scripting hooks

Cra registers the `cra://` scheme so it can be driven from a shell:

    open "cra://action/newTab"              # any action id from KeyBindings.swift
    open "cra://commandbar?query=github"    # open the command bar with text
    open "cra://open?url=https://example.com&background=1"   # a tab behind; Cra stays where it is
    open "cra://open?url=https://example.com&little=1"   # in a Little Window
    open "cra://open?url=https://example.com&space=<space id>"   # in that space (its id in sidebar.json)
    open "cra://import?source=arc&archive=1&settings=1"  # headless import
    open "cra://dismiss"                    # close sheets, command bar, find bar

Links from other apps and browsers only reach `commandbar`, `dismiss` and `open` with an
http(s) URL; pages inside Cra reach none of them. The rest (`action`, `navigate`, `key`,
`import`, `debug`) run scripts and DevTools Protocol commands, so they need either
`defaults write dk.kildahl.cra scriptingURLs -bool YES` or a test instance's
`CRA_COMMAND_FILE`. See `AppDelegate.isUserFacing` before adding a host.

## Rendering calibration

`open "cra://debug?lift=0&liftInactive=0.75&alpha=1&material=13&state=follows&appearance=dark"`
changes the vibrancy parameters live (see `Sources/Cra/UI/Tuning.swift`). `material` is the
raw `NSVisualEffectView.Material` value, `alpha` scales the gradient opacity.

## Brand assets

Logo sources are in `brand/` (see `brand/README.md`). `resources/brand/*.png` are WebKit
renders of them (so the multiply blends survive) used by `BrandMark`, and
`resources/AppIcon.icns` is built from `brand/cra-segments-icon.svg` (render at 1024 px,
`iconutil`). The marketing site lives in a separate private repository.

## Releasing

`scripts/release.sh` builds, signs with a Developer ID, notarizes, and packages a DMG and
zip into `build/dist`, for Apple silicon and Intel. Pushing a `v*` tag runs the same through GitHub Actions and
publishes a release. Releases with UI changes get short clips on the release notes first
(`scripts/clips`, `.claude/skills/release-clips`). See [release.md](release.md) for the
one-time certificate setup.

## MCP

See [Agents in Cra (MCP)](mcp.md) for setup, tools and access boundaries.
