# Reviewing a pull request

What a review of a change to Cra checks, in the order to check it, and what decides whether it
gets in. It applies to contributors' PRs and to our own work alike. The rules come from
[CONTRIBUTING.md](../CONTRIBUTING.md), [CLAUDE.md](../CLAUDE.md) (the layers) and
[testing.md](testing.md). This page says how to check them.

A review ends with one of four verdicts: **merge**, **merge with a fixup** (we push the small
fix to the branch ourselves), **changes requested**, or **close**. Each verdict says which items
below passed, which failed, and how each was checked.

## 1. Fit

- **One thing.** A PR that also refactors, renames or reformats around its change is split, or
  the extra part is dropped.
- **In scope.** No cloud AI, no account, no server, no telemetry: nothing leaves the Mac
  (CONTRIBUTING.md has the one exception, Tidy Tabs on Apple Intelligence). A feature bigger
  than a bug fix had an issue or a discussion first.
- **Off-limits unless it's the point:** the release pipeline, signing, the CEF pin in
  `scripts/fetch-cef.sh`, `scripts/cef-patches`. A change that needs a new CEF patch is
  discussed before it's written; the maintainer builds CEF.
- **No secrets** in code, fixtures or test data, and no real browsing data in `Tests/Fixtures`.

## 2. Arc parity

Arc is the default spec. A PR that changes something Arc has must match Arc's layout, colours,
shortcuts, animations and hover states, at 1x and 2x.

- **Check Arc itself, not the PR's description of it.** Read what we already measured in
  [arc-reverse-engineering.md](arc-reverse-engineering.md) and [arc-parity.md](arc-parity.md).
  When those don't cover it, look at Arc:
  - On screen: Arc and Cra captured on the same display at the same scale, 1x as well as 2x
    (glyphs that match at 2x can land between pixels on a 1x external display). Animations come from recordings, frame
    by frame, not from watching them.
  - Inside Arc, when the state is hard to reach on screen: Arc's Swift classes keep their field
    names (`otool -oV` on the arm64 slice lists each class's ivars), and the disassembly shows
    which layer goes into which. That is how #234 was settled: Arc's `FolderIconView` inserts its
    `_customIconLayer` into the front panel's layer, under the front shading.
- **The PR shows both apps.** For anything visible, the description has Arc next to Cra (a
  screenshot, or a clip for motion). A screenshot of Cra alone doesn't show parity. When the
  author can't run Arc, the reviewer makes the comparison.
- **New facts go in the docs.** What the review learned about Arc goes into
  arc-reverse-engineering.md, with the date and how it was measured.
- **Deviations are decided, not slipped in.** Arc isn't the only source of truth: a change that
  does better than Arc can get in, but only as a stated deviation that Victor agrees to. A
  feature Arc never had is built from Arc's parts (its rows, pills, menus, spacing, animations),
  not from another browser's look. Some deviations are on purpose (favorites per space, the
  hidden sidebar's wider reveal strip): before taking a PR that moves Cra back toward Arc, check
  arc-reverse-engineering.md and the history of the lines it changes.

## 3. Native and fast

Cra is AppKit and Core Animation wherever speed shows. In 0.1.18 the sidebar list, space pager,
pane toolbar and command bar rows moved from SwiftUI to AppKit, and the time the main thread
spent on six space swipes went from about 1900 ms to 440 ms. Keep it that way.

- **AppKit for anything repeated, scrolled or animated:** sidebar rows, lists, toolbars, glyphs,
  anything that moves with a gesture. Rows are layer-backed views reused by key. SwiftUI is fine
  for forms and one-off panels (Settings, onboarding, import, the space editor, the Library)
  where nothing runs per frame. A new SwiftUI view inside the sidebar list, or an
  `NSViewRepresentable` per row, is a request for changes.
- **Layers over views** for the parts of a glyph or row: `CAShapeLayer`, `CAGradientLayer`, a
  `CALayer` with `contents`. No `NSImageView` or extra subviews where a layer does.
- **Nothing expensive per frame or per update.** Rasterize an image once and cache it, keyed on
  what changes it (image, colour, size, backing scale). Guard model updates with equality before
  touching views. No layout passes, path rebuilds or image draws on animation frames or scroll.
- **Core Animation hygiene.** A colour or opacity change on a layer we own runs in a
  `CATransaction` with actions disabled, or it animates for 0.25 s (lint:
  `layer-colour-outside-transaction`). An animation that should animate says so explicitly.
- **Pixel-aligned at 1x.** Sizes and positions land on whole pixels (`px()` rounding as in
  `FolderGlyphView`). Fractional SF Symbol sizes and drawing-handler images drawn into an
  `NSImageView` look thin and off-centre at 1x.
- **The main thread never waits** on disk, the network or a Chromium round trip. Timers go
  through the app's `Scheduler` (lint: `timer-outside-scheduler`).
- **Memory and process counts stay flat.** Closing tabs returns helper processes to baseline;
  scenarios check this. Anything that holds a page, a profile or a large image says when it
  lets go.

## 4. Code

- **Layers ([CLAUDE.md](../CLAUDE.md)).** Decisions with no window or page go in CraCore with a
  test; a type that needs AppKit for part of its job is split; a decoder reads only its own
  file; CraCore never imports AppKit (lint: `core-platform-import`). A PR that touches one of
  the "known exceptions" may move that piece; it doesn't have to.
- **Data-folder formats.** A change that makes `sidebar.json`, `settings.json`,
  `windows.json` or the other files load differently updates the fixtures in
  `Packages/CraCore/Tests/CraCoreTests/Fixtures/Model` and says why in the PR. Old files must
  still load.
- **Matches the code around it.** Naming, structure, comment style. Doc comments say *why*,
  and an Arc-derived value says where it came from. No dead code, debug prints, commented-out
  code or leftover flags.
- **Correct in the cases that aren't the demo:** light and dark, every theme and the White and
  Black folder icon styles, 1x and 2x and moving between them, row reuse (a row taking a
  different item must drop the old one's state), empty and huge inputs, a window that isn't key.
- **Security.** Pages never reach `cra://` actions or native APIs they shouldn't
  ([SECURITY.md](../SECURITY.md)); nothing new is written outside the data folder; downloaded
  or imported data is treated as untrusted.
- **Small enough to read.** Moving code between files is fine when the PR says so, and the
  review diffs the moved code against the original rather than reading it as new.

## 5. Tests

- **A bug fix comes with a test that fails without it** ([testing.md](testing.md) rule 5).
  Don't take the PR's word for it: put the bug back (revert the fix, or re-create the defect in
  the new code) and run the test. It must fail with a message that names the bug.
- **The right layer.** A decision is a table test in CraCore. A view's contract (its layer
  tree, geometry, pixels) can be a harness that compiles the production file on its own, like
  `scripts/test-folder-glyph.sh` or `scripts/test-peek-dim-panel.sh`. A journey is a scenario.
  No test hooks added to windows just to reach a decision (testing.md rule 2).
- **A new harness is wired in:** a `suite` line in `scripts/test.sh`, `CRA_TEST_SWIFTC_FLAGS`
  and `CRA_TEST_KEEP` in its script so the sanitizers and coverage see it, and a line in
  [development.md](development.md#tests).
- **Gates:** changed lines under test ≥ 70 %, CraCore ≥ 85 % (`scripts/coverage.py`). No
  sleeps, no wall clock, no assertions on a fake's bookkeeping alone.
- **Issues are locked.** A fix for a GitHub issue tags its test `.bug(".../issues/<n>")` (or
  `// promise: #<n>`) and runs `scripts/promises.py --update`. A PR that changes a locked test
  is changing behaviour that shipped: stop and ask Victor (testing.md rule 8).
- **What no test can reach** (a real site, the GPU, a person's eye) is a line in
  [release-checklist.md](release-checklist.md), and the PR says so.

## 6. Run it

- **Merge it with current `main` locally and run `scripts/test.sh`.** A green CI on an old base
  isn't enough.
- **Build it and look at it** (`scripts/build.sh`, a test copy with its own `CRA_DATA_DIR`).
  Check the change itself, the states around it (open and closed, hover, selected, light and
  dark, 1x and 2x), and Arc next to it. Tests passing is not validation.
- **Scenarios** for anything touching tabs, windows, the sidebar store or start-up:
  `scripts/scenario.sh <name>` on a release build.

## 7. Docs and follow-through

- New behaviour is described where people look: `docs/` for developers, the help centre for
  users (crabrowser.app/help), arc-parity.md when a parity gap closes.
- A UI change needs a release clip before it ships (`scripts/clips`).
- When it merges: squash-merge with the author kept as author, reply on the PR (and the issue)
  saying what got in and any fixup we made, and credit the author by name in the release notes
  of the release that ships it.

## A review, written down

#234, the live folder's mark turning with the folder's front panel:

    Verdict: merge

    Fit: one thing. FolderGlyphView moved to its own file unchanged apart from the emblem
         (diffed against the old class). ✓
    Arc: Arc's FolderIconView inserts _customIconLayer into the front panel's layer, under the
         front shading (field names and disassembly of Arc's binary). The PR does the same. ✓
         The PR had no Arc capture; the binary settled it.
    Native: a CALayer replaces an NSImageView; the image is rasterized once per
         (image, ink, size, scale) and reused on every toggle. ✓
    Code: nits only. FolderEmblem's .original colouring and relativeSize have no caller yet,
         and the test images are solid colours, so an upside-down emblem would still pass
         (checked on screen instead).
    Tests: new harness, 59 checks, wired into test.sh with sanitizer and coverage flags. Putting
         the emblem back outside the front panel fails "every emblem corner must follow the front
         panel's perspective". ✓
    Ran: test.sh on the PR merged with main ✓. Release build, live folder closed and open,
         captured next to main's: closed identical within 2/255, open now on the panel. ✓
    Follow-through: release clip of a live folder opening; credit Grigoriy (@STRENCH0).
