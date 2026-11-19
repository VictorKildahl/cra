# Cra: notes for coding agents

[CONTRIBUTING.md](CONTRIBUTING.md) says what fits (Arc parity by default, no cloud AI,
nothing leaves the Mac) and how to send a change. [docs/development.md](docs/development.md)
has the layout and the tests, and [docs/testing.md](docs/testing.md) has the test rules.
[docs/reviewing.md](docs/reviewing.md) is what a PR review checks (Arc parity, AppKit over
SwiftUI, tests that fail without the fix) and how. This file holds the layer rules.

## Layers

| Layer | Where | Imports |
|---|---|---|
| Core | `Packages/CraCore` | Foundation, CoreGraphics, Observation |
| App | `Sources/Cra` | CraCore, AppKit, SwiftUI, CraCEF |
| Bridge | `engine/chromium/cra` (built into Chrome's framework) | Chrome and content (Objective-C++), seen by Swift through `Sources/CraCEF/include/CraCEF.h` |
| Bridge on CEF | `Sources/CraCEF/CraCEF.mm` | CEF, while `CRA_ENGINE=cef` builds remain |
| Helper on CEF | `Sources/CraHelper` | CEF (the engine uses Chrome's own helpers) |
| iPhone | `iOS/Cra` (+ `iOS/CraWidgets`, `iOS/CraShare`) | CraCore, UIKit, SwiftUI, WebKit |

CraCore never imports AppKit, Cocoa, SwiftUI, UIKit or CraCEF. `scripts/lint.py`
(`core-platform-import`) fails the build when it does. CraCore is a package of its own, so
`swift test --package-path Packages/CraCore` runs without `vendor/engine` or `vendor/cef`. Every app file sees it
through `Sources/Cra/App/CraCoreExports.swift`.

The iPhone app matches Arc Search the way the Mac app matches Arc, and its decisions live in
`Packages/CraCore/Sources/CraCore/Mobile/` under the same rules. [docs/ios.md](docs/ios.md) has
its layout and `scripts/ios.sh` (build, run, screenshots, UI tests); its status is
[docs/ios-parity.md](docs/ios-parity.md). Its UI suite takes over ten minutes and loads the Mac:
run the classes a change touches, and the whole suite in halves.

1. **Decisions go in CraCore.** Code that decides something without a window or a page (a
   model, a file format, a layout rule, a policy) goes in CraCore, with a test. Its API is
   `public` because the app is another package.
2. **Split a type that needs AppKit for part of its job.** The value goes in CraCore and the
   AppKit side becomes an extension in the app: `KeyChord` and `Shortcut`, `FaviconKey` and
   `FaviconCache`.
3. **A decoder reads only its own file.** A one-time migration that needs anything else
   (another app's preferences, the disk) takes it as an argument and runs where the file is
   loaded. Example: `AppSettings.migrateToolbarDefault(arcShowsToolbar:)`, called by
   `SidebarStore`.
4. **Data-folder formats don't change by accident.**
   `Packages/CraCore/Tests/CraCoreTests/Fixtures/Model` holds current and older
   `sidebar.json`, `settings.json`, `windows.json`, `keybindings.json` and the others. Each
   comes with what Cra saved after loading it. If a change makes a file load differently,
   record the new expectation and say why in the PR.
5. **Run `scripts/test.sh` before a PR.** CI runs it as well, with the coverage gates in
   docs/testing.md.
6. **Every bug fix comes with a test that fails without it.** That applies whether the bug
   came from an issue, an X DM, a crash report, a nightly failure or your own testing. Write the
   test first, see it fail on the unfixed code, then fix. When the bug has an issue, tag the test
   `.bug(".../issues/<n>")` (`// promise: #<n>` above a harness func or an iPhone UI test,
   `# promise: #<n>` in a scenario) and run `scripts/promises.py --update`, so it's locked in `Tests/promises.lock`.
   A crash report without an issue is locked the same way under a crash ID:
   `.bug(id: "crash-<what-crashed>")`, `// promise: crash-<what-crashed>` or `# promise: crash-<what-crashed>`.
   When the decision can't be reached by a test, move it into CraCore (rule 1) or add the
   `cra://debug` readout a scenario needs as part of the fix. Only what needs a real site, the
   GPU or a human eye becomes a line in docs/release-checklist.md, and the commit says so.
   When a locked test fails, the change broke something that shipped: fix the change, not the
   test. Only Victor decides that a shipped behaviour changes; then run
   `scripts/promises.py --update` and name the issue in the commit (docs/testing.md rule 8).
7. **Everything built and everything reported gets a test.** A feature, on the Mac or the
   iPhone, reported or not, ships with tests that pin what it does: CraCore for the decision, a
   harness, UI test or scenario for the wiring. A report whose code turns out to be right still
   gets the test that proves it, tagged with its issue. On the iPhone that is both: the decision
   in CraCore `Mobile/` with a `.bug` test, and the UI test with `// promise: #<n>` above it.
   Nothing is done, or pushed, without its tests; the reply on the issue names the test.
8. **What pages ask the browser for keeps working.** Uploads, print, dialogs, prompts and choosers broke in
   0.1.49 (#571, #574) because Chrome read its never-seen window and nothing tried them.
   [docs/web-features.md](docs/web-features.md) maps every way a page reaches its browser to its test
   (`Tests/web-features.tsv`). A change to how Cra hosts pages runs `scripts/scenario.sh web-features` first; a
   new page feature gets its row and scenario; `scripts/release.sh` won't release a build that fails them.

## Known exceptions

This logic is pure enough for CraCore but still lives in the app. Move a piece when a change
touches it anyway, not as a side errand.

- `Services/SuggestionEngine.swift`: the command bar's ranking. It holds `SidebarStore`,
  `KeyBindingRegistry` and `SearchSuggestions`.
- `Services/SidebarStore.swift` and `SidebarIntegrity.swift`: tree edits and repair, on
  `JSONStore` files, the app's clock and `ArcImporter`. Tested by `scripts/test-store.sh`.
- `App/KeyBindings.swift`: `KeyAction`, `MenuSection` and the default bindings, in a file that
  imports AppKit for `Shortcut`'s event matching.
- `Services/Import/`: the parsers for other browsers' files. Tested on `Tests/Fixtures` by
  `scripts/test-store.sh`.
- `UI/Windows/ExtensionLaunch.swift` and `Services/DevToolsToggle.swift`: policies, tested by
  `scripts/test-policies.sh`.
