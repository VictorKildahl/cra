# Cra: notes for coding agents

[CONTRIBUTING.md](CONTRIBUTING.md) says what fits (Arc parity by default, no built-in AI,
nothing leaves the Mac) and how to send a change. [docs/development.md](docs/development.md)
has the layout and the tests, and [docs/testing.md](docs/testing.md) has the test rules. This
file holds the layer rules.

## Layers

| Layer | Where | Imports |
|---|---|---|
| Core | `Packages/CraCore` | Foundation, CoreGraphics, Observation |
| App | `Sources/Cra` | CraCore, AppKit, SwiftUI, CraCEF |
| Bridge | `Sources/CraCEF` | CEF (Objective-C++, seen by Swift through `include/`) |
| Helper | `Sources/CraHelper` | CEF (the Chromium subprocess) |

CraCore never imports AppKit, Cocoa, SwiftUI, UIKit or CraCEF. `scripts/lint.py`
(`core-platform-import`) fails the build when it does. CraCore is a package of its own, so
`swift test --package-path Packages/CraCore` runs without `vendor/cef`. Every app file sees it
through `Sources/Cra/App/CraCoreExports.swift`.

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
- `UI/Windows/ExtensionLaunch.swift`, `Services/DevToolsToggle.swift` and
  `UI/Windows/FloatingSidebarGeometry.swift`: policies, tested by
  `scripts/test-policies.sh` and `scripts/test-floating-sidebar.sh`.
