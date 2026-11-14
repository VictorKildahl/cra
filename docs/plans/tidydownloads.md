# Tidy Downloads: Arc parity on Apple Intelligence

Status: independently reviewed with the bounded implementation clarifications below; coordinator may authorize source changes. No source implementation or commit is authorized by this document alone.

Scope: the existing Tidy Downloads feature only. Keep local Apple Intelligence, native download rename, the current opt-in setting, download history and undo. No new feature, provider, network request, setting, CEF patch or broad refactor.

## Evidence and current behavior

| Contract | Arc evidence | Cra at base `fccc893` | Planned result |
|---|---|---|---|
| Helpful filename | Retained prompt `0x1039929d0`: roughly 2–4 words, preserve informative names, remove machine IDs/copy suffixes, simplify dates/timestamps/casing/spacing; nine examples. | Similar instructions, six substitute examples. | Reproduce the recovered behavioral instructions and nine example cases in the local model prompt. Two–four words remains guidance; useful source information may require more. |
| Context and language | Request builder `0x1002d5c00`: filename, source domain (full URL fallback), web-contents title or referrer title; localized response language with English fallback. | File, clipped `item.displayTitle`, host from the source tab address; no referrer fallback or language instruction. | Capture actual page title and existing referrer title at first observation, preserve source URL, choose the page title then referrer fallback, and explicitly name output language. |
| Structured response | Typed `{newName: string}`. | FoundationModels `@Generable TidyDownloadAnswer.name`. | Keep guided generation, use `newName`, describe it as the proposed filename; deterministic native code owns suffix protection. |
| Original suffix | `0x1002d6b38` saves the original final-dot suffix including its dot; `0x1002d488c` always removes the model's final-dot suffix, even when the original suffix is empty. | A changed suffix is appended to instead of replaced; an extensionless original can gain an extension. | Apply Arc's literal final-dot algorithm, preserving original suffix spelling, including empty/trailing-dot cases. |
| Validation | `0x1002d63d8` rejects empty/dot-prefixed basenames and unchanged final names. | Also normalizes whitespace/quotes, substitutes `/` and `:`, rejects overlong answers. | Keep existing path and length safeguards around the corrected suffix contract. Do not invent MIME/type inference or multi-extension special cases. |
| Collision | `0x1002d4fc4`: unchanged proposal first, then ` (1)` through ` (100)` before final suffix. | ` 2` through ` 999`, returns the occupied proposal on exhaustion. | Match spelling and bounds; return no destination if all candidates exist, without overwriting or advertising success. |
| Side effects | Sibling destination, filesystem operation, `DownloadData.localURL` update, concrete reverse operation. | File move, `DownloadHistory.move`, recent-download callback, rename banner and revert exist. | Reuse the existing path; commit state/banner only after successful file move; undo updates all the same references. |
| Cancellation | `0x1002d59b4` checks `Task.isCancelled` before delivering the rename action; state metadata has cancel/setup/teardown. | Unretained inference task; setting/model/owner eligibility is checked only before inference. | Retain tasks by download request, invalidate on opt-out/owner teardown/terminal cancellation, and check eligibility again before moving. |

Evidence files (read in this worktree's planning pass):

- `/Users/varunaditya/Desktop/arc-decomp/CRA_COMPARISON.md`, Tidy Downloads rows and suffix/opt-out findings.
- `/Users/varunaditya/Desktop/arc-decomp/AI_FEATURES.md`, download request and deterministic extension notes.
- `/Users/varunaditya/Desktop/arc-decomp/reports/ai-bundle-evidence.md:80–139`, complete download pipeline and limits of recovered UI click evidence.
- `/Users/varunaditya/Desktop/arc-decomp/reports/ai-pipeline-evidence.md`, shared pipeline context; no additional download-specific behavior inferred from another feature.
- `/Users/varunaditya/Desktop/arc-decomp/inventory/Arc.arm64.__cstring.tsv:1090–1120`, exact prompt, examples, schema, and context labels.
- `/Users/varunaditya/Desktop/arc-decomp/decompiled/Arc.arm64/chunks/0010.c:73861`, request/title fallback/language; `:73033`, model final-dot stripping; `:74202`, validation; `:73505–73620`, collision loop starting at 1 and ending at 100.
- `docs/arc-reverse-engineering.md`, “Tidy Downloads (Arc 1.171, 4 Nov 2026)”: on-screen geometry, animation, timings, and explicit previously approved deviations.

The exact file-manager dependency method and full banner-click-to-undo static edge are unresolved in Arc. Native file move, model mutation and reverse-file operation are independently established. Do not present unresolved edges as new facts.

## UI contract

Keep `DownloadRenameCard` (AppKit/Core Animation), `SidebarView` presentation and the existing Settings row. The behavior changes should feed corrected names through these surfaces, without redesigning them.

| Surface | Acceptance |
|---|---|
| Banner text | “Download renamed to:”; new filename semibold; old filename struck through; “Revert to original name” and close controls; clicking the body reveals the renamed file. |
| Placement | Sidebar minus 8 pt on each side; tail anchored above the download bin; no layout change when filename contains localized text, emoji or a long name. |
| Motion | Existing spring from the tail, sparkle treatment and delayed strike retained; roughly 8 s dismissal and existing hover hold retained. |
| Approved deviations | Preserve 71 pt body height, dark-space `#929BFF` secondary text and hover hold with at least 3 s after leaving, explicitly requested by Victor on 5 Nov. Do not silently restore Arc's 65 pt body or lower-contrast blue. |
| Revert | File restored to original name or next free Arc-style sibling; history and recent path restored; existing “Download name reverted!” toast only on success. |
| Off/unavailable | No automatic file mutation or new rename banner. Keep existing Settings availability explanation and opt-in behavior. Shared Max settings layout belongs to the coordinating work and must not be rewritten here. |
| Multiple completions | Preserve current one-card presentation: the latest applied rename replaces it in its owner window. Do not introduce a notification queue. |

Run the existing long/short filename snapshots first. Compare Arc and Cra on the same display at 1x and 2x, light/dark, narrow/wide sidebar and a non-key window. Record the source of each measurement: current live Arc capture, existing Arc recording, or static evidence. An unchanged snapshot proves preservation, not newly measured Arc fidelity. Light-space card appearance and Arc hover behavior were not measured; retain the documented Cra treatment.

## Implementation design

### 1. Filename rules in CraCore

Keep `TidyDownloads` as the owner of pure request assembly, output validation and candidate naming. Add only the small pure request/state values needed to test this feature's production decisions.

For cleaning: perform existing outer quote/whitespace/path normalization; remove everything after the final `.` in the proposed name (including that dot), if present; reject empty or dot-prefixed basename; append the original final-dot suffix exactly, or empty suffix; apply current length/path/unchanged guards to the final filename. Use an explicit string final-dot helper rather than `NSString.pathExtension`, whose hidden/trailing-dot interpretation differs from the recovered split-on-dot algorithm. Preserve interior dots and original suffix case. Examples with no generated suffix remain valid.

For collision candidates: proposal, `Stem (1).ext`, …, `Stem (100).ext`; apply the same final-dot rules to extensionless, multi-dot and trailing-dot names. Make exhaustion explicit with an optional result. Both forward rename and revert must handle `nil` as failure/no mutation. File existence is a query; successful `moveItem` remains authoritative if another process occupies a candidate after the query. Do not overwrite, delete the conflicting file, or retry indefinitely.

Do not add extension allowlists, filename heuristics, a hard two–four-word validator or downloaded-content parsing. Arc's examples describe model behavior, not a second hand-written renaming engine.

### 2. Prompt, source context and guided generation

Use separate labeled original filename, source domain and source title fields, mirroring Arc's recovered request. Keep the full source URL in the in-memory context to derive host/full-URL fallback; do not substitute the active tab at completion. Prefer a captured page title (`TabData.savedTitle`) over the user's custom sidebar name; trim emptiness and use the captured existing referrer title when absent. `TabData.referrerID` already supplies a same-store reference; do not add a persistent field or CEF bridge API. Capture source once so navigation, renaming or closure during download cannot change its meaning. Fall back to the actual download URL when no source tab exists. Bound every variable request field (filename, source domain/full-URL fallback, source title and language) with explicit modest feature-local limits and test them; preserve useful Unicode at grapheme boundaries. These short inputs do not justify a shared context-fitting framework. Account for the fixed nine examples and guided schema in the request allowance; record any unavailable-model token-fit limitation rather than claiming character caps guarantee a fit.

Arc uses an English locale to spell the output language and falls back to English. Pass the selected language into the pure prompt builder; resolve the system language in the app, not in a unit test. Localize generated filename values only. Interface strings and schema keys stay English, per repository policy. The local FoundationModels adapter remains behind `#if canImport(FoundationModels)` and macOS 26 availability, uses guided `newName` and current greedy generation. No remote calls or API keys.

Replace the fake-model parser's dependency on the prompt's last quoted line with the same typed request values used in production. This is needed to keep the existing scenario truthful after changing the prompt; it is not evidence of actual Apple Intelligence output quality.

### 3. Request ownership and application

Retain an in-flight task and request identity for each download/owner window. A new generation token must prevent a late completion from removing or applying a newer request. Reject duplicate completion notifications; keep the existing exactly-once intent. Retire source context on every terminal outcome, including disabled/unavailable completion, cancellation and interruption. Avoid retaining source titles indefinitely for failed downloads or retaining a completed task's closures/store/window.

Use the existing observation mechanism for the owner's `tidyDownloads` preference: switching it off invalidates current work immediately, so off-then-on cannot revive the old response. Cancel/remove owned requests on window teardown; closing only the source tab does not cancel an already captured, still-owned download. Use current model availability again on completion. Immediately before filesystem mutation, require: current request identity; not cancelled; setting still enabled; model still available; owner still eligible; original file still at expected path. Stop on missing/moved file, invalid answer, inference failure or exhaustion. A cancelled provider may still produce an answer; guards must protect the file regardless.

Keep the filesystem boundary minimal: a private serial queue or actor plus a small move-result value is sufficient; do not add a coordinator, transaction journal, operation registry or generic command hierarchy. Perform filesystem existence/move work away from the main thread through that feature-local seam; keep model/history/recent/banner publication on MainActor. Serializing this feature's file moves avoids two simultaneous completions choosing the same free path, while `moveItem` still handles external races. Do not create a generic file-operation framework. Ensure cancellation during an already completed file move cannot leave disk renamed but history stale: revalidate before beginning the move, then finish the matching state publication or reconcile the completed operation rather than discarding it. This seam must return the actual source/destination result and permit direct tests of on-disk outcomes.

Reuse `DownloadHistory.move` and the existing owner callback; no alternate history model or automatic second rename. Preserve log privacy: counts/errors only, no filenames, titles, full URLs or generated text added to diagnostics.

### 4. Undo

Use the same destination rules and bounded collision search. Only dismiss/publish success and show the reverted toast when the reverse filesystem operation succeeds; a missing file, permissions failure or exhausted destination must not falsify history. Verify recent-download ID/path before updating so a newer download is untouched. Preserve unrelated history entries and thumbnails. Repeated/stale undo must be harmless: require the current rename identity and matching recorded download/history path, then consume/invalidate that rename after successful revert. A rename UUID and path do not identify a file replaced externally at the same path. If asserting protection against that external replacement, capture and compare a filesystem resource identifier in the existing rename record; otherwise explicitly leave external path replacement outside the guarantee. Do not create a separate identity registry or pretend the current path alone proves file identity. Do not add an undo stack or new UI.

## Fail-first validation

Write the focused regression first, run it on the unfixed production code and save its failing output. Then implement and show the same check passing. The existing incorrect `Ladybug.png.jpeg` expectation must change because this task explicitly authorizes Arc suffix parity. `TidyDownloadsTests.swift` currently has no issue tag and is not in `Tests/promises.lock`; keep other locked download tests unchanged. If a needed change reaches a locked test, identify the issue and update only its authorized changed behavior and lock entry, with the issue in the subject as repository rules require.

| Layer | Cases and observable assertions |
|---|---|
| Core suffix | `Ladybug.png` + `AdobeStock_1.jpeg` → `Ladybug.jpeg`; generated suffix + extensionless original → extensionless result; matched/mismatched uppercase suffix; no generated suffix; multi-dot `archive.tar.gz`; interior dot; original trailing dot; generated trailing dot; `.pdf`/dot-prefixed/empty basename; unchanged final result; quotes/Unicode/whitespace/path/length guards. Verify literal final-dot semantics even when they look less clever than type-aware handling. |
| Core collision | Proposal free; original occupied then `(1)`; gaps; `(100)` last free; all 101 names occupied → `nil`; extensionless and trailing/multi-dot names; no existence query past `(100)`. Assert actual returned destination, not only call counts. |
| Core request | Filename, source domain/full-URL fallback, page-title/referrer fallback, missing context, language with English fallback, deterministic Unicode bounds, untrusted quote/newline content kept as data, schema/instructions/example intent. Test semantic fields rather than pinning an entire prose blob. |
| Request lifecycle | A controllable suspended model allows opt-out, off/on, unavailable state, owner teardown, duplicate finish, obsolete completion, provider error and cancellation ignoring provider to complete in any order. Assert the actual eligibility decision and no disk/history/banner change; no sleeps. Normal out-of-order different downloads remain independent. |
| Real temporary filesystem | Forward move changes real file location, preserves bytes, leaves original absent, returns actual destination; collision files untouched; missing source/error/exhaustion leaves original and state; two completing downloads cannot overwrite each other. Undo restores bytes/path and changes only matching history/recent entry; occupied original chooses `(n)`; failed/stale/repeated undo does not show success or move unrelated files. |
| App integration/scenario | Existing `tidy-downloads` journey and long/short rename card snapshots; add meaningful scenario assertions/readout for actual file path/history/revert if needed, using the existing production boundary. Exercise download from source tab then navigate/close that tab; destination/source-context must remain captured. Retain existing dock preview checks. |
| Manual model/visual | With real Apple Intelligence enabled, compare recovered prompt cases for informativeness, machine cruft, dates and language; inspect actual disk/history/banner/undo. Compare Arc/Cra visual states and animation. No fake-model run can certify this row. |

Prefer existing CraCore tests for pure policies. For asynchronous app/file behavior, compile the production feature-local seam against minimal model/store/UI dependencies in a focused harness, following existing `scripts/test-*.sh` conventions. New harness must honor `CRA_TEST_SWIFTC_FLAGS`/`CRA_TEST_KEEP`, be wired into `scripts/test.sh`, and be documented in `docs/development.md`. Avoid a large fake app or tests that assert only fake calls. Use continuations/manual scheduler for asynchronous ordering; introduce no timing sleeps in decision tests.

Run targeted tests with an external scratch directory to avoid concurrent shared `.build` use. The coordinator owns full `scripts/test.sh`, build, release scenarios and CEF dependency work. Do not trigger a CEF download or concurrent full build from this feature branch. Final integration runs `git diff --check`, promises, lint, full required tests, release build and `scripts/scenario.sh tidy-downloads`; retain failures unrelated to this feature as separate findings instead of silently fixing them.

Current host Apple Intelligence is off. Deterministic tests and fake-model scenario validate wiring only. Real naming quality, locale quality and actual inference remain unverified until an enabled eligible Mac runs them; mark that explicitly in review and the relevant release-checklist entry.

## Granular commit and review sequence

Do not commit this plan before independent review. Do not begin implementation until the coordinator relays the plan review and resolves findings. Each item below is one measurable conventional subject-only commit after its own independent code/redundancy review, focused fail-first evidence and scoped diff inspection. No push before that review.

| Order | Proposed subject | Included work | Required evidence before commit |
|---|---|---|---|
| 1 | `fix(downloads): preserve Arc filename suffix rules` | Final-dot helpers/cleaner and suffix regression tables; correct existing divergent assertion. | New cases fail on old cleaner, pass on fix; all focused core download tests; unchanged safety cases; no MIME guesses. |
| 2 | `fix(downloads): match Arc collision naming` | Optional bounded candidate search; forward/revert exhaustion handling; collision tests. | `(1)`/`(100)`/exhaustion fail first; temp-file collision preservation; all call sites handle no candidate. |
| 3 | `feat(downloads): match Arc rename prompt context` | Recovered semantic prompt/examples, language and typed source/referrer capture, guided `newName`, fake-model adaptation. | Prompt/fallback tests; actual source-tab routing inspection; no unrelated Max settings edit; adapter compilation in coordinated app build. |
| 4 | `fix(downloads): discard obsolete rename requests` | Feature-local request ownership, cancellation/recheck/cleanup, owner integration, necessary asynchronous harness. | Suspended-provider failure first for opt-out/obsolete result; duplicate and owner teardown tests; no leaked tasks/context; current request cannot be cleared by stale completion. |
| 5 | `fix(downloads): keep rename and revert state consistent` | Off-main-thread move boundary if not completed with request work; actual file/history/recent/card/undo consistency, failure and simultaneous-move handling. | Real temporary-file contents/path assertions; successful and failed undo; external collision races; no disk/history divergence after cancellation. |
| 6 | `test(downloads): verify Arc rename and undo integration` | Only necessary scenario/readout changes and docs describing evidence, remaining real-model limitation and supported behavior. | Coordinated complete tests/build/scenario, preserved snapshots and Arc/Cra evidence; issue locks unchanged unless explicitly authorized behavior requires it. |

Move a directly dependent test/seam into the commit that needs it so each commit compiles and demonstrates its own behavior. Do not use the sequence to postpone a broken call site or undo regression. The independent reviewer must examine redundant helpers, duplicate state, dead generation paths, overbroad fake dependencies, unbounded bookkeeping and any UI change beyond this plan. Review findings are fixed and re-reviewed before each commit/push. The coordinator controls integration and publication.
