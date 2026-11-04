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
1 GB of disk for CEF and the build products.

`scripts/fetch-cef.sh` pins the CEF version and downloads it into `vendor/cef` (not
committed). It fetches Cra's own CEF build, made by `scripts/build-cef.sh` with H.264/AAC
and the patches in `scripts/cef-patches` and published as a `cef-*` release by
`scripts/publish-cef.sh`; `CEF_URL` points it at Spotify's stock build instead. A daily workflow (`.github/workflows/cef-updates.yml`) opens an
issue when a newer stable CEF is out; `scripts/update-cef.sh` moves the pin.

## Layout

- `Sources/Cra` — the app: `App` (delegate, key bindings), `Services` (sidebar store,
  persistence, import, updates, extensions, live folders), `UI` (sidebar, command bar, split
  view, windows, settings, onboarding)
- `Sources/CraCEF` — Objective-C++ bridge between Swift and CEF
- `Sources/CraHelper` — Chromium subprocess executable
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
`keybindings.json`, cached favicons, the logs and a Chromium profile folder. Delete it to
start over.

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
    Tests/smoke-launch.sh            # launches build/Cra.app three times, about 30 s
    scripts/scenario.sh all          # user journeys in build/Cra.app, about 6 minutes
    scripts/scenario.sh sleep-tabs   # one of them (Tests/Scenarios/<name>.scenario)
    scripts/coverage.py              # line coverage, and the changed-lines gate against origin/main
    scripts/coverage.py --base <ref> # the same against another base (CI passes the PR's)
    scripts/fuzz.sh                  # mutated importer fixtures under AddressSanitizer
    scripts/mutate.py [word]         # mutation testing of the pure code, minutes; a word limits it

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
- `scripts/test-perf.sh`: the performance recorder on a real main run loop: injected stalls,
  hang files with a `sample` stack, the session marker, ownership, the recording switch
  ([performance.md](performance.md)).
- `scripts/lint.py`: Cra's own rules (testing.md), checked by `scripts/test.sh`.
- `Tests/smoke-launch.sh [app]`: starts the app on a throwaway data folder with no pages,
  with a page opened, then with it restored, and quits it like ⌘Q after a settings write.
  It fails on a crash, a hang, an error exit or a new crash report, which is how a `CHECK`
  inside Chromium shows up. Its own data folder lets it run next to your daily Cra.

What none of these see: compositing (the sidebar blur), fullscreen spaces, and how real sites
behave. Check those by hand, and say how in the PR.

Scenario hooks for a command file (`cra://debug?…`): `checkStore=1` logs a fault per broken
sidebar link, `pageJS=<js>` runs script in the focused page, `installExtension=<folder>` and
`removeExtension=<id>`, `extensionAction=<id>`, `fullscreen=1|0`, `windowSize=1280x800`,
`snapshot=<ViewClass[,n]>&out=<png>`, `sleepTabs=<seconds>` (the 10 tabs used last too), `memoryPressure=warning|critical` (one
memory-pressure sweep at that level, if Settings ▸ Tabs has it on), `stall=<ms>` (blocks the main
thread), `perfReport=<path>` (the recorder's perf.json now), `systemAppearance=light|dark|system`
(the appearance Auto space themes follow, without changing the Mac's), `themeEditor=1` (Edit
Theme Color… for the focused space), `relaunch=1` and `quit=1`.

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

Tidy Tabs needs Apple Intelligence. `CRA_TIDY_FAKE_MODEL=1` stands in a model that groups by
site (after a 1.6 s pause), so a test instance on any Mac shows the button, the squiggle and the
groups, and Tidy Tab Titles names a pinned tab after its title's first part; `CRA_TIDY_FAKE_MODEL=off` (or `preparing`, `ineligible`) shows Settings ▸ Max as a Mac
without Apple Intelligence would. `cra://debug?tidy=1` runs Tidy on the window's space without
hovering the divider, `cra://debug?undoTidy=1` is ⌘Z's undo and `cra://debug?settingsPane=max`
opens Settings on a pane.

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

## Scripting hooks

Cra registers the `cra://` scheme so it can be driven from a shell:

    open "cra://action/newTab"              # any action id from KeyBindings.swift
    open "cra://commandbar?query=github"    # open the command bar with text
    open "cra://open?url=https://example.com&background=1"
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
zip into `build/dist`. Pushing a `v*` tag runs the same through GitHub Actions and
publishes a release. Releases with UI changes get short clips on the release notes first
(`scripts/clips`, `.claude/skills/release-clips`). See [release.md](release.md) for the
one-time certificate setup.
