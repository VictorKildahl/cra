# Tidy Tab Titles implementation plan

Status: independently reviewed with the bounded clarifications below; coordinator may authorize implementation. No implementation or commit is authorized by this plan alone.
Branch: `tidytabtitles`, based on `fccc893ca3989ebed0485dd9a67622fa7950f0c9`.
Inspected: 12 November 2026. Keep this branch limited to automatic names assigned when a tab is pinned.

## Outcome and boundaries

- Request Arc's cleaned `filtered` and short `rewritten` alternatives in the user's language.
- Select the most informative candidate that fits the actual native row's title width.
- Prevent disabled, cancelled, superseded, manually renamed or no-longer-pinned work from applying a name.
- Retain the existing native reveal, sparkles, subtitle, settings switch, pin trigger and local-only model.
- Preserve deterministic `TidyTitleRules` and its 52-site data, persistence format, other Max features and unrelated UI.
- Do not change ordinary pinned navigation semantics. A pinned name may intentionally describe its home.
- Do not add a new setting, cloud provider, dependency, generic AI orchestration layer, telemetry or CEF change.

## Evidence and current behavior

Read `CLAUDE.md`, `CONTRIBUTING.md`, `docs/testing.md` and `docs/reviewing.md`. Decisions belong in CraCore; native measurement belongs in the app. Fixes require a regression test seen failing before the fix. New harnesses must enter `scripts/test.sh` and `docs/development.md` and support coverage/sanitizer flags.

| Area | Arc evidence | Current source inspected | Planned disposition |
| --- | --- | --- | --- |
| Prompt | `arc-decomp/inventory/ai/feature-prompts.json`, strings `0x103987ae0`, `0x103987b50`, `0x103987b80`; builder `0x1000c00ac` in `chunks/0002.c:40548` | `Packages/CraCore/Sources/CraCore/TidyTitles.swift` asks for one 1–4-word answer in the page's language and supplies six observed outputs | Port the recovered instructions' meaning and two fields. Replace these style examples rather than maintaining competing old/new prompt contracts. |
| Candidate construction | `reports/ai-bundle-evidence.md:49–64`; `0x1000bf6a4`, `chunks/0002.c:40000` compares field character counts | `TidyTitles.clean` accepts a single answer only when at most 40 characters and shorter than the shown title | If both valid fields exist and filtered has fewer characters, retain filtered alone; otherwise retain filtered then rewritten. Deduplicate normalized equivalents. Remove the 40-character and shorter-than-shown rules. |
| Width | `0x1000bff80`, `chunks/0002.c:40468` chooses largest measurement fitting width, smallest measurement otherwise; measurement function is `0x1007726e8` | `TabRowView.layout` uses 14pt native text and `TabRowTrailing.layout`, accounting for depth, slash, sound and trailing accessories | Native text measurement, pure measured-width choice. Character counts only govern Arc's candidate construction, never the final width selection. |
| Manual names | Handler `0x1000be2ac` existing optional-title branch at `0002.c:39579`; supporting manual-rename error | `TidyTitlesService` requires unnamed before and after generation, still pinned and same shown title | Keep these protections. Add request token and feature-enabled recheck. |
| Lifecycle | Arc keeps loading/pending-title state; three-second Combine branch relates to reveal/hints, not proven model timeout | `pending: Set<UUID>` and unretained `Task`; cancellation swallowed by `try?`; no opt-out recheck | Retain request tasks and scheduled reveal cleanup. Cancel work on opt-out, invalidate its token and reject late results. |
| UI | `docs/arc-reverse-engineering.md:3805–3839` records live Arc 1.171: ~1s pin-to-reveal, 0.55s sweep, ~3.1s further subtitle | `TabRowView.playTidyRename`, `Effect`, `delayAfterPin=1`, `sweep=0.55`, `subtitleShown=3.65` already implement those measurements | Keep geometry/motion constants. Fix title fit and interrupted effect cleanup only where needed for the feature; compare visible output before making any further adjustment. |
| Trigger | Recovered product is automatic rename on pin; exact drag timing less certain | `SidebarStore.moveItem` calls `tabPinned` only entering Pinned, unnamed, not incognito; `Tests/StoreTests.swift:1621` covers it | Keep trigger and existing pin-hook tests. No rename for moves within Pinned. |
| Context | `CRA_COMPARISON.md:24,40` flags character caps and opt-out gap | Existing prompt clips only title to 200, not host; fresh model session; generic catch | Bounded complete request with one context-overflow recovery; no long page body or fetch. |

`AI_FEATURES.md`, `CRA_COMPARISON.md`, `reports/ai-bundle-evidence.md` and `reports/ai-pipeline-evidence.md` were checked against raw title prompt, candidate and width functions. These are local evidence under `/Users/varunaditya/Desktop/arc-decomp`, not artifacts to copy into the repository.

Evidence limits: Arc's extra candidate predicate is unresolved; do not claim our validation exactly reproduces it. Rendered text width is a strong inference from the native measurement helper, not a recovered source declaration. Preserve the repository's existing reveal measurement, whose recordings are stronger timing evidence than a guessed decompiler timeout. Arc's old six examples were observed outputs, not its recovered few-shot prompt.

## Design

### 1. Core request and response contract

Keep `TidyTitles` as the titles-only pure namespace. Introduce a small public response value carrying `filtered` and `rewritten` strings, plus candidate/selection functions. The app's `@Generable` answer has those same two fields and converts to that value. Use guided field descriptions; do not request JSON text and parse it again.

The recovered instructions require:

- Edit, summarize and translate a bookmarked tab's title.
- Remove site name unless it is the only useful content, SEO cruft and page-kind words such as video/recipe/guide.
- Preserve specifics and proper nouns, with context; retain subject/main verb/direct object where possible.
- `filtered`: translated title with cruft removed and **no word-count rule**.
- `rewritten`: rewritten title in **1–3 words**.
- Write values in the user's language, while keeping schema keys stable.

Pass title, site/host and response language as bounded input data. Keep the generated result separate from the data and identify source text as untrusted content, so a page title cannot replace the transformation instructions. The request contains no page body or network call.

Resolve `Locale.preferredLanguages.first` to an English-localized language name in the app, matching Arc's `en_US` localized-language lookup; use English if missing/unresolvable. Pass the resolved language into the pure prompt builder so tests do not depend on the machine's locale. This localizes generated content only; Cra's interface remains English.

Normalize each field to a single display line: trim surrounding whitespace/quote wrappers, collapse internal whitespace, reject empty/control-only input, and deduplicate case-insensitive equivalents. Preserve meaningful punctuation and proper nouns. Do not enforce an English whitespace word count on CJK output. The guided rewritten field and prompt express the word constraint. Keep an explicit generous technical output bound to reject pathological generations; document it as local resource safety, not Arc's filtered word limit. Confirm the smallest sensible bound during review (proposed 512 characters per field with a 384-token response reserve).

Apply Arc's candidate-count relation after normalization. Select by positive finite native widths: largest width `<= availableWidth`; when none fit, smallest width; stable original order for ties. Ignore invalid widths. Return nil for no valid candidates or a selected name equivalent to the title already shown; do not silently substitute a different candidate just to force a rename. No title mutation or effect when there is no change.

### 2. Native width integration

Keep AppKit measurement in the app. Extract only the reusable title geometry needed by `TabRowView.layout`, retaining `TabRowTrailing` as the authority for controls. Do not duplicate a sidebar-width-minus-magic-number estimate in the service.

- Add a narrow `TabRowView` accessor returning the current title font and drawable text width, excluding `SidebarText.inset` padding, after layout. Use the actual label's font and measurement attributes.
- Add a narrow lookup on `SpaceListView`, reusing its existing weak `all` list and keyed `views` dictionary. Match item ID and the window captured when pinning, so another window cannot determine the persisted name.
- Resolve width at result application, not at generation start, so a resize during inference uses the current row layout. One layout/measurement pass per generated result, none per animation frame.
- Measure the two cleaned candidates with AppKit, feed the resulting numbers into CraCore's selector, then apply the chosen name through `store.rename`.
- For an unmaterialized row, derive the same width from the list's row model and shared production title geometry if possible. If the originating window/list no longer exists, use zero available width and the measured smallest-candidate fallback. Document this fallback; do not invent a global width or hold a completed request indefinitely waiting for a view.
- Factor native measuring/width lookup behind a small injectable closure in `TidyTitlesService`, used both by the shared production instance and lifecycle harness. Do not place AppKit imports in CraCore or add UI solely for testing.

If extracting shared geometry would expand into accessory construction refactoring, stop at the current label accessor and explicitly test/document the smallest-candidate behavior for nonmaterialized rows. This is a bounded implementation choice for the reviewer, not permission for a broad row rewrite.

### 3. Request lifecycle and effects

Use a dictionary keyed by tab ID, containing task, request token and scheduled reveal/cleanup handles where needed. Keep the existing one-request-per-tab behavior. A task may not remove or complete a newer entry sharing its ID.

Capture original shown title, pinned home identity (`savedURL`), originating window and request token. The current pin callback carries only the item ID: resolve and capture `store.activeWindowID` synchronously at the real pin event when that identifies its initiating window, and document the fallback for programmatic pins. Do not choose the current key window later at result time or expand every tree-edit API merely to thread UI context. Completion policy in CraCore receives simple values: enabled, cancelled/current token, item exists, pinned, custom name absent, shown title unchanged, pinned home unchanged. Compare pinned home identity, not ordinary live URL navigation. Explicit home replacement with the same title invalidates the old request; ordinary navigation away from the same home remains allowed under the existing shown-title rule.

Use `store.clock.now` and `Scheduler.after` for minimum reveal delay and subtitle expiry; keep existing durations. No `Task.sleep`/wall-clock test dependency. Cancelled model work must return immediately through the task's cancellation path; do not swallow cancellation then schedule a reveal.

Opt-out must cancel tasks and scheduled pending reveals, clear associated effects and invalidate request tokens before any result can apply. Re-enabling does not rename already pinned tabs and never revives the previous request. Add one feature-specific settings change callback in `SidebarStore.settings.didSet`, invoked only on `tidyTabTitles` changes, and wire it beside `store.tabPinned` in `AppDelegate`. This catches the individual switch, Turn Off Max and any other settings mutation; no UI-specific toggle interception and no shared observer framework. Tests must prove this hook fires for the real store.

Manual rename, removal and unpin are rechecked before mutation and suppress both rename and effect. They need not add new callbacks throughout the store solely to cancel an otherwise bounded in-flight model call. The model request's maximum output and one-retry policy bound that work. Service teardown cancels owned tasks and scheduler handles. Reveal cleanup must be token-safe; row reuse/edit interruption must not leave masks or sparkles on a later item. Only modify the existing row cleanup if its scoped regression actually fails.

### 4. Context budget and error handling

The installed SDK was inspected directly: `FoundationModels.swiftinterface` exposes `tokenCount(for: instructions/prompt/schema)` on macOS 26.4+, `contextSize` on macOS 26.0 with back deployment, `maximumResponseTokens`, and typed `GenerationError.exceededContextWindowSize`.

- Bound title, host and resolved language inputs (proposed initial title 200 characters, host 253, language 64); retain grapheme boundaries.
- On macOS 26.4+, count the fixed instructions, actual prompt and generated schema using the model's public APIs. Reserve 384 response tokens and a small conservative transcript margin; fit to `SystemLanguageModel.default.contextSize`. Reduce title context deterministically rather than dropping locale or output schema. If fixed cost alone does not fit, skip safely.
- On macOS 26.0–26.3, use the same bounded short request; character limits are a fallback, not a token guarantee.
- On typed context overflow only, retry once with a freshly constructed session and smaller title context (for example 100 then 50 as needed by the counted fitting path); never retry cancellation, refusal, unsupported language, unavailable assets or arbitrary model failures.
- Keep retry/shrink decisions pure and testable in CraCore using small titles-only functions or values; this short input needs no prompt-part framework, budget object hierarchy, general fitter or separate lifecycle state machine. The app performs SDK token counting and generation. No public tokenizer dependency and no attempt to derive a tokenizer from UTF-8 length.
- Recheck cancellation and request identity between counting, retry, minimum-delay scheduling and final mutation. Log failure category without page title/URL/output. Preserve graceful no-rename behavior.

The exact cap/margin values are implementation parameters to validate against a working local model. No claim of output quality or precise preflight token parity is justified on the currently disabled-model host.

## Files and tests

| File | Intended changes |
| --- | --- |
| `Packages/CraCore/Sources/CraCore/TidyTitles.swift` | Prompt/locale input, response candidate construction, measured selection, bounded retry and completion policy. Keep titles-only decisions together unless readability requires a small adjacent file. |
| `Packages/CraCore/Tests/CraCoreTests/TidyTitlesTests.swift` | Replace obsolete one-field assertions; keep deterministic rule tests untouched; table-test candidates, widths, prompt bounds, locale fallback inputs and completion/retry decisions. |
| `Sources/Cra/Services/TidyTitlesService.swift` | Structured response, retained tokenized tasks, native width callback, cancellable scheduler work, typed overflow recovery and feature stop. Keep fake-model mode deterministic with both fields. |
| `Sources/Cra/UI/Sidebar/List/SidebarRowViews.swift` | Narrow native title metrics accessor/shared geometry only; scoped effect cleanup only if the regression demonstrates need. No visual redesign. |
| `Sources/Cra/UI/Sidebar/List/SpaceListView.swift` | Originating-window/item layout lookup using existing native lists. |
| `Sources/Cra/Services/SidebarStore.swift`, `Sources/Cra/App/AppDelegate.swift` | Single setting-change callback and wiring next to the existing pin callback. |
| `Tests/StoreTests.swift` | Real-store opt-out callback and existing pin trigger coverage; home replacement versus normal navigation guards where production inputs can be exercised. |
| `Tests/TidyTitlesServiceTests.swift`, `scripts/test-tidy-titles.sh` | Focused production-service contract harness with controllable async answer, ManualScheduler, fake store/availability/native metrics only at real dependency boundaries. Check applied names/effects, not fake call counts alone. |
| `Tests/Scenarios/tidy-titles.scenario`, made-up page fixture if required | Fake-model pin/rename journey using existing scripting actions and logs; persistence and native row snapshots where supported. No new debug-window hook. |
| `scripts/test.sh`, `docs/development.md` | Register/document the focused harness, honoring `CRA_TEST_SWIFTC_FLAGS` and `CRA_TEST_KEEP`. |
| `docs/arc-reverse-engineering.md`, `docs/arc-parity.md`, `docs/release-checklist.md` | Date/source the recovered contract, mark actual completed parity narrowly and list human checks/model limitations. |

Regression cases, each with a meaningful output assertion:

1. Long but fitting filtered title can be chosen even beyond the old 40-character/shorter-only restrictions.
2. Filtered shorter than rewritten produces filtered alone; equal counts keep both; missing/empty/duplicate fields behave deterministically.
3. Two candidates: both fit, only one fits, neither fits, exact boundary, equal widths, zero width, invalid measurements; CJK and `WWW`/`iii` establish that width differs from character count.
4. Locale input differs from title language; unavailable locale gives English; long title/host/language remain bounded; fixed instructions preserve proper-noun/site-removal rules.
5. Completion rejected for opt-out, cancellation, old token, manual rename, unpin, deletion, changed displayed title or changed pinned home. Ordinary navigation does not independently invalidate a same-home request.
6. Deferred async response delivered after opt-out cannot rename or add an effect. Disable/re-enable and a new pin cannot let old completion remove the new task or effect.
7. Advance ManualScheduler around the one-second reveal and subtitle expiry boundaries. Cancel during pending delay; cancelled cleanup cannot clear a later effect.
8. Typed overflow takes one smaller retry; a second overflow stops; generic failure/cancellation does not retry; counted-budget fitting preserves schema/language and reserves output.
9. Result arriving after resize uses new native metrics; a different window's width is not used; missing materialized row takes the documented smallest-width fallback.
10. Pin via existing command/store path persists the chosen custom name; manual name remains unchanged; moves within Pinned do not generate another request. Check row reuse/sweep cleanup visually or in an existing native-view harness if safely reachable.

For fixes, write the applicable test before implementation, run it against baseline and retain the exact expected failing assertion in review notes. Prompt changes are feature behavior rather than evidence that a model will obey it. Do not alter existing locked issue tests without the user's required approval.

## Granular commit sequence and mandatory review gates

Each row is a coherent conventional commit, subject only. Before **every** commit and push: independent reviewer examines actual diff plus test evidence, explicitly removes redundant/unneeded code (or requests its removal), checks scope and returns a verdict. Resolve that review before committing; root coordinates commit/push permission and review. Do not squash unrelated changes into this branch.

| Step | Proposed subject | Reviewable contents and required checks |
| --- | --- | --- |
| 1 | `feat(titles): match arc title candidates` | Two-field request and guided response, language, bounded prompt, pure candidate construction and measured-width selector; switch service response atomically so no broken one-field caller. Focused core tests and compile/typecheck changed service. |
| 2 | `feat(titles): fit names to native sidebar width` | Narrow row/list metrics integration and production service choice; tests for width selection/window/fallback, native row inspection at multiple widths. No geometry changes to neighboring rows. |
| 3 | `fix(titles): cancel disabled rename requests` | Retained tokenized work, setting hook, scheduler delays, completion/home guards and contract harness; baseline-failing opt-out and stale-request tests, real store hook tests, focused lint. |
| 4 | `fix(titles): recover from context overflow` | SDK-gated counted budget and one bounded retry; pure fitting/retry tests and production-service harness outcomes; cancellation recheck across retry. |
| 5 | `test(titles): cover pinned title parity` | Scenario/native evidence, only necessary scoped cleanup fixes accompanied by failing regressions, dated docs/release checks; complete coordinated validation. Omit this commit if its contents fit coherently into earlier commits and no distinct useful work remains. |

The plan itself remains uncommitted until the root's independently reviewed plan gate is satisfied. If splitting would leave an intermediate revision uncompilable, move the minimal required adapter into that earlier commit; do not add temporary compatibility machinery.

## Validation and delivery evidence

During implementation use a scratch build outside the worktree:

```sh
swift test --package-path Packages/CraCore --scratch-path /tmp/cra-tidytabtitles-core --filter 'TidyTitleRulesTests|TidyTitlesTests'
scripts/test-tidy-titles.sh
scripts/test-store.sh
python3 scripts/lint.py
git diff --check
```

Coordinate disk/build use with root: approximately 22 GiB was available at task start; do not download/build CEF or run full `scripts/test.sh` concurrently with other feature branches. Root coordinates full tests, release build and a relevant scenario before delivery; no passed result is assumed in this plan.

| Manual check | Evidence and acceptance |
| --- | --- |
| Arc versus Cra at 1x/2x, same display/width | Side-by-side actual title rows/settings captures; narrow/wide rows, depth and accessories. Larger valid candidate fits without avoidable truncation; smallest fallback is documented. |
| Native rename reveal | Clip/frame checks: original clipped text sweeps into chosen title, sparkles end, hint appears/expires; preserve existing 0.55s sweep and 3.65s subtitle interval unless new Arc evidence warrants change. |
| Interrupted UI | Edit/delete/unpin/disable must suppress a late rename/effect. Switching spaces/windows alone may complete valid work, and resizing uses the current originating-row width. Closing the originating window follows the documented smallest-candidate fallback for a surviving pinned tab; it cannot use another window's width or show an effect on an unrelated reused row. No masks/sparkles may survive row reuse. |
| Settings/model unavailable | Off-by-default persisted setting and existing availability behavior unchanged. Turn Off Max and individual title toggle both suppress queued mutation. |
| Real local model | On a model-enabled Mac, try branded home page, proper-noun article, SEO-heavy title, another-language title and CJK. Record actual filtered/rewritten behavior, fit and translation; do not infer quality from a fake. |
| Persistence | Relaunch disposable `CRA_DATA_DIR`; custom chosen title survives, deterministic title rules still work when Max is off. |

Initial inspection found Apple Intelligence disabled; later verification on 12 November found the local model available. Four calls through the actual production adapter/schema returned English Arc/Anna names, Spanish `Clima`, and Japanese-script alternatives. The Japanese filtered result retained “guide”, so semantic cleanup remains imperfect. Fake-model mode can demonstrate control flow, native layout, cancellation and persistence, but **cannot** validate semantic quality, translation, real latency or model context recovery. Screenshots or successful builds alone do not establish output quality or lifecycle correctness. No commits/pushes or claims of completed parity occur before independent reviews and actual checks.
