# Testing

How Cra is tested, what runs when, and the numbers that gate a change (GitHub #44, #45).
Commands for each piece are in [development.md](development.md#tests).

## Rules

1. **Test the decision, not the doing.** What decides (which tab to select, whether a tab
   may sleep, which buttons a toolbar has) is a value type with a table test. What performs
   it (an `NSView`, a CEF call) gets no unit test; scenarios cover it.
2. **Only test at seams that exist in production.** When logic can only be reached by building
   a window, move the logic (into CraCore like `ToolbarComposition`, or a policy like
   `ExtensionLaunch`); don't add a test hook to the window.
3. **No sleeps, no wall clock.** Decisions taken from time use the app's clock
   (`Scheduler`, injected through `AppComposition`); a test passes a `ManualScheduler` and
   advances it, so the 30-minute archive pass runs in a millisecond.
4. **Fixtures over dictionaries.** Every format Cra reads from another browser has a made-up
   profile in that browser's own format under `Tests/Fixtures/<Browser>` (no real browsing
   data). Parsers are tested on those files, and the fuzzer mutates them.
5. **A bug fix comes with the test that would have caught it**, written first and seen failing
   on the unfixed code. That holds for every bug, with or without an issue; one with an issue, or
   from a crash report, is also locked (rule 8). If no test can reach it, the fix moves the decision into CraCore or adds
   the debug readout a scenario needs; only what takes a real site, the GPU or a person's eye
   becomes a line in [release-checklist.md](release-checklist.md).
   The same goes for everything built and everything reported: a new feature (Mac or iPhone,
   asked for or not) ships with tests that pin it, and a report that turns out not to be a bug
   still gets the test that proves the behaviour, tagged with its issue (CLAUDE.md rule 7).
6. **Never assert on a fake's bookkeeping alone.** A test whose only check is "the fake
   recorded a call" tests the fake.
7. **A flaky test is rewritten on the clock or deleted**, never retried or given a sleep.
   `scripts/test-store.sh` runs every test in one process on one data folder, and a store saves
   0.4 s later in real time: a new store loads whatever earlier tests' saves have landed, their
   clocks hours ahead of yours. A test that reads state it didn't make puts it on disk itself
   (`saveAll()`) so it is there every time, then copes with it (`startAfterLoadedTabs`, a change
   that flips a setting instead of assuming it is off). Stress such a test with ten copies of the
   kept binary at once (`CRA_TEST_KEEP`): two checks passed alone and failed most of those runs.
8. **What a closed issue shipped is pinned.** The test that proves an issue's fix carries
   `.bug("https://github.com/VictorKildahl/cra/issues/<n>")` (`// promise: #<n>` above a harness
   func or an iPhone UI test in iOS/CraUITests), and `Tests/promises.lock` holds a
   hash of each such test (`scripts/promises.py`, run by `scripts/test.sh` and by a hook before
   every `git push`). Changing, renaming or deleting one fails until `scripts/promises.py --update`;
   do that only when the issue's behaviour is meant to change, say why in the commit and tell the
   reporter. 0.1.30 rewrote the #155 test together with the change that broke it, and nothing
   failed until the reporter wrote back.
   A fix for a crash report with no issue is pinned the same way under a crash ID, `crash-` and a
   few lowercase words naming the crash: `.bug(id: "crash-perf-counter-overflow")`,
   `// promise: crash-zen-favicon-size` or `# promise: crash-fedcm-dialog` at the top of a scenario.
   #111's crash came back with the engine switch; the crash fixes after it had tests, but nothing
   kept those tests as they were. `Tests/test_promises.py` tests the lock itself.
   What no test can pin yet is a manual check in [release-checklist.md](release-checklist.md).

## Layers

| Layer | What | Where | Runs |
|---|---|---|---|
| L0 static | `scripts/lint.py`: the bug classes below as rules | `scripts/test.sh` | every PR |
| L1 unit | `Packages/CraCore`: pure types, `swift test` | `scripts/test.sh` | every PR |
| L2 contract | production files compiled against fakes: browser manager, store and importers on a manual clock, policies | `scripts/test-*.sh` | every PR |
| L3 component | Arc-specified views drawn from the running app and compared with `Tests/Snapshots` | `scripts/scenario.sh snapshots` | release, nightly |
| L4 scenario | the real app driven through a journey, invariants only | `scripts/scenario.sh` | one per PR, all nightly |
| L5 human | the sidebar blur, fullscreen Spaces, GPU, real sites | the PR description | each PR, release |

L0–L2 need no CEF and finish in about 20 seconds. L3 lives in the running app because Cra's
views can't be compiled without most of the app; it draws each view's layer tree (no blur,
no page content), so it checks geometry, ink and fills.

## Gates and budgets

- **Changed lines under test ≥ 70 %** (`scripts/coverage.py`, posted on the PR). Of the lines a
  PR adds or changes in files a harness compiles, at least 70 % must run. Changed files no
  harness compiles (views, CEF glue) are listed, not counted.
- **CraCore ≥ 85 % of lines.** There is no target for the whole repo: one would be met by
  testing the easy files.
- **Mutation score ≥ 70 %** (`scripts/mutate.py`, weekly): one operator flipped at a time in
  the pure code must fail a test. About a thousand mutants are more than the CI job's hour, so
  it tests a shuffled sample for 70 minutes (`CRA_MUTATION_MINUTES`), a new order each ISO week.
- **Scenario invariants**, the same for every scenario: the app is still running at the end,
  no new crash report for its processes, no `fault:` line in `cra.log`, the sidebar sound
  (`SidebarIntegrity`), main-thread stalls inside the scenario's budget, Cra's memory inside
  its budget, helper processes back to baseline five seconds after tabs close, the performance
  recorder under 0.1 % of a core (`selfCost.cpuPct` in its perf.json, `budget perfcpu=`) with its
  count of 250 ms stalls within a few of HitchMonitor's, and a quit within 20 seconds that ends
  without a signal (#227: ReportCrash can take longer to write its report than the run waits).
  The budgets are for a release build (`scripts/build.sh`), which is what the nightly runs: a
  debug build's recorder costs about six times as much (0.16–0.22 % against 0.03–0.04 %, 6 Nov
  2026), so on a debug build the recorder line fails and means nothing.

Stall budgets are set from what the app does today, so they catch regressions rather than
describe a goal. The count of stalls over 50 ms is steady from run to run and carries the
budget; the longest stall swings with machine load (235 ms one run, 498 ms the next), so it
only has to stay under 1.5 s, and start-up under 1 s. GitHub's macOS runners are slower than
a desk Mac (sleep-tabs: 1016 ms longest, 52 over 50 ms), and the budgets fit both. On 1 Nov 2026 every new tab blocked the main thread for
about 100 ms, the first page shown for up to 330 ms, and turning developer mode on or off
130–650 ms; `fifty-tabs` and `sleep-tabs` carry counts that allow the first. Lower the
budgets as those get faster. Stalls right after a `snapshot` line are the snapshot being
drawn and don't count.

## Lint rules

`scripts/lint.py` grandfathers existing code in `Tests/lint-baseline.txt`: a file that gains
a finding fails, and when one loses a finding the baseline comes down
(`scripts/lint.py --update-baseline`).

- `layer-colour-outside-transaction`: a colour or opacity set on a `CALayer` Cra made itself,
  outside a `CATransaction` with actions disabled, animates for 0.25 s.
- `timer-outside-scheduler`: `Timer.scheduledTimer` in `App/` or `Services/`.
- `wall-clock-in-decision`: `Date()` in the store, tab sleep or live folders.
- `raw-observation-tracking`: `withObservationTracking` outside CraCore's
  `observeChanges(of:apply:)`. A struct copied out before the closure is never tracked.
- `importer-without-fixture`: an `…Importer` with no profile under `Tests/Fixtures`.
- `core-platform-import`: `Packages/CraCore` importing AppKit, Cocoa, SwiftUI, UIKit or CraCEF
  ([CLAUDE.md](../CLAUDE.md) has the layers).
- `perf-no-network`: networking under either Perf folder. The performance recorder never sends
  anything ([performance.md](performance.md)).
- `perf-boundary`: the recorder reached from a file outside its list, or `CraCEF` imported in
  `Sources/Cra/Perf` anywhere but `PerfCEF.swift`, so it stays removable and testable.

## Faults

`CraLog.fault("…")` is for a state the code assumes never happens: a file that can't be read
or written, a sidebar whose links disagree. It writes a `fault:` line to `cra.log` instead of
failing silently. Scenarios fail on any, and `CRA_FAULT_TRAP=1` makes a debug build stop at
one. Every launch checks the sidebar and logs a fault for each broken link.

## Scenarios

    scripts/scenario.sh fifty-tabs      # one
    scripts/scenario.sh all             # every one, about 6 minutes
    CRA_SCENARIO_SHARD=2/4 scripts/scenario.sh all   # every 4th from the 2nd (Nightly runs 4 per backdrop)
    scripts/scenario.sh web-features    # what pages ask the browser for: a release's gate

A scenario (`Tests/Scenarios/*.scenario`) is a list of `cra://` commands plus a few
directives (`wait`, `repeat`, `budget`, `helpers`, `relaunch`, `expect-log`, `snapshot`, `seed`, `env`,
`arg`, `extension`, `home`; the header of `scripts/scenario.sh` lists them). It runs `build/Cra.app` on a throwaway data
folder, behind your windows (`CRA_TEST_BACKGROUND`), with the fixture pages served from
127.0.0.1. Logs, hitch log and snapshots land in `build/scenarios/<name>/`. Adding a journey
is a text file; the invariants come for free.

`web-features` runs the scenarios `Tests/web-features.tsv` names: every way a page reaches its browser (file
pickers, print, dialogs, permission prompts, device choosers, full screen, sharing, payments, passkeys), each
tested over Cra's own windows rather than Chrome's never-seen one. Every release runs them on its own build and
stops on a failure; [web-features.md](web-features.md) has the map, the gates and the readouts.

The `extension-link-context`, `extension-peek-context`, `extension-little-window-context`
and `extension-split-window-context` scenarios check password-manager context. A content
script asks its real extension service worker for the current and last-focused tab,
then compares their IDs with the sender's tab, including duplicate URLs and an inactive
sender. They cover links, Back, background tabs, Peek closing/parking/expansion, Little
Window promotion, split-pane focus and browser-window closing. They run in the background
on throwaway profiles; `scripts/scenario.sh <name>` runs one without the rest of the suite.

`auto-theme` flips the app between light and dark (`cra://debug?systemAppearance=`) and reads
which half each window draws (`cra://debug?themeShown=<label>`): an Auto space must switch its
window content and sidebar both ways, and a Light one must not (#155).

`fullscreen` takes over a Space and runs only with `CRA_SCENARIO_SCREEN=1` (CI does).
So do `pip-window-covered` and `pip-window-minimised`: a background copy reports every window
visible, so automatic Picture in Picture of a window out of sight only runs on screen. They cover
the window with `cra://debug?coverWindow=` and play `sound-video.html`, the fixture that makes sound
(#117, #533).
`CRA_FLAGS=backdrop=material` runs any scenario on the sidebar's `NSVisualEffectView` path
instead of the private `CABackdropLayer` one (`FeatureFlags`); nightly runs both, so a macOS
that breaks the private path fails a run instead of shipping.

## Component snapshots

`component-snapshots` imports the made-up Arc profile, sizes the window and draws the space
header, favorites, sidebar rows, dock, URL pill, the toolbar in its normal, developer and
split-pane forms and the split row, plain and being renamed. A difference over 0.05 % of
pixels fails, with a red diff image next to the new snapshot.

References are drawn at 2x, so snapshots are judged and recorded only with the test window on a
Retina screen. On a 1x display (an external monitor that `CRA_TEST_SCREEN` picks) the view's text
and images are drawn at 1x and scaled up, so the scenario writes `<name>.1x.png`, notes "not
compared" and refuses `CRA_SNAPSHOT_RECORD=1`.

`scripts/scenario.sh snapshots` runs every scenario with a `snapshot` line, one at a time, with
`CRA_SNAPSHOTS=strict`: a snapshot that differs, or couldn't be compared, fails even though budgets are
only noted; a scenario that fails runs once more, and one that passes then is listed as "passed only the second
time" (sidebar-parity's dark tiles drew a pixel apart once in about ten runs). It opens the copies on a 2x display: `CRA_TEST_SCREEN` when it names one, else the first one
connected, else the virtual 2x "Cra Test Display" (`scripts/test-display.sh`), taken away afterwards.
`scripts/release.sh` runs it after the web features, while Apple notarizes, and stops the release on a
failure (`CRA_SKIP_SNAPSHOTS="<why>"` releases anyway; say why in the notes). Before it, nothing ran these
scenarios before a release: two references went stale on main unseen when PR #678 gave the Arc fixture its
icons (22 Nov 2026). A fixture change (`Tests/Fixtures/Arc`, imports) or a drawing change runs it too.

A reference is Cra's own drawing, so it can only be as right as Cra was when it was recorded.
Before recording one again (`CRA_SNAPSHOT_RECORD=1 scripts/scenario.sh component-snapshots`),
compare that view with Arc 1:1 on screen, and put both in the PR.

## Nightly

`.github/workflows/nightly.yml`: every scenario on both backdrop paths, the harnesses under
AddressSanitizer, ThreadSanitizer and UBSan (`CRA_TEST_SWIFTC_FLAGS`), 400 000 fuzzed inputs
(`scripts/fuzz.sh`), and on Mondays mutation testing. Xcode's toolchain has no libFuzzer on
macOS, so the fuzzer mutates the fixtures itself with a fixed seed; a crash leaves its input
in `build/fuzz/crash-input`.

On GitHub's runners the scenarios run with `CRA_BUDGETS=report`: budgets (stalls, memory, the
recorder's cost) and snapshot differences go in the job summary but don't fail the job, because
they were set on a Mac and a runner VM measures differently (macOS 26.7.2 draws system symbols a
few pixels apart; one system sample there costs 11–27 ms of CPU against under 1 ms on a Mac).
What the app does fails it: `expect-log`, faults, crash reports, a page crash ("Aw, Snap!") in
the recorder's `perf.json`, helper counts, quitting. Judge budgets and snapshots with a release
build on a Mac.
