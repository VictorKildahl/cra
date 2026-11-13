# Ask on Page implementation plan

Status (13 November): the R0 reconciliation plan was approved. R1 native integration, R2 eligibility/synchronous ownership, R3a guarded exact DOM quote operation, R3b native input/layout and R3c standalone CoreGraphics import are independently reviewed and committed through `653ed22bf6c5f4482fca9ceaf8a9143ace6eea8e`. R4 adds integrated tests and the [validation record](../ask-on-page-validation.md). Root release builds, the full WMO suite, actual isolated CEF/WebKit script matrices and bounded native routing/generation journeys passed. The reviewed implementation may be published with the recorded limitations; native full-literal highlighting/selection, physical Find-panel key/focus and visual/motion acceptance remain OPEN. Model quality failures remain recorded. Neither complete parity nor the overall goal is complete. Earlier design/batch statements remain historical where the approved reconciliation amendment supersedes them.
Branch: `askonpage`, original base `fccc893`; upstream `426c34552a72a1e30da672e42811a90943e190a7` merged by reviewed R1.
Worktree: `/Users/varunaditya/.codex/worktrees/cra-askonpage/cra`.

## Outcome and scope

Restore Arc's Ask on Page inside the existing Cmd-F Find panel, powered only by the Mac's
on-device `SystemLanguageModel`. Preserve ordinary Find, next/previous matches, Use Selection
to Find and Jump to Selection. Add the single opt-in Max feature and the page-grounded,
streaming conversation it needs. No cloud client, account, API key, URL refetch, persistence of
chat/page text, telemetry expansion, general assistant, cross-tab answering or other Max work.

Read before planning: `CLAUDE.md`, `CONTRIBUTING.md`, `docs/reviewing.md`, `docs/testing.md`;
current Find implementation, ShellView ownership/layout, BrowserManager isolated evaluation and
navigation revision, WebKit find implementation, Max settings/model availability, existing
local streaming model services and production-file test harnesses.

## Evidence and limits

The local primary corpus is `/Users/varunaditya/Desktop/arc-decomp` (Arc 1.171.0 arm64).
These files were actually inspected, rather than relying on feature names:

| Evidence | Contract it supports |
| --- | --- |
| `AI_FEATURES.md`, original-five table | Cmd-F entry, page conversation, quote citations, short answer, local reimplementation replaces original provider. |
| `reports/ai-pipeline-evidence.md:9-24` | Page extraction, language, bounded context/history, streaming/cancellation and quote navigation models. |
| `inventory/Arc.arm64.__cstring.tsv:20658-20708`, addresses `0x103a3b9f0` through `0x103a3c260` | URL/current date/title/content/BEGIN DIALOGUE; exact research-assistant prompt; standalone excerpt tags; roughly ten-word answer; bold answer term; guesses identified; preferred language; translation/summary permitted; solar/borough/privacy/summary examples. |
| Same inventory `20708-20716`, addresses `0x103a3c320`, `0x103a3c3e0`, `0x103a3c400`, `0x103a3c430` | Error text, “Ask a question…”, long-page disclosure prefix, quote-not-found warning. |
| `inventory/Arc.arm64.swift-fields.tsv:29359-29432` | Messages/typing/fractionOfContextUsed/messageLoading; content/window/space identity; matches; quotesSearched; conversation state; quote plain text/search state/find closure; focus token. |
| `decompiled/Arc.arm64/chunks/0175.c:37783-37824` | Outstanding thread tasks cancelled and removed. |
| Same chunk `38310-38385`, `38546-38830`, `38837` onward | Bounded extraction, minimum readable content check, context construction, history omission, prompt fitter and async streaming. The recovered literal `0x1000` does not establish Apple's token budget. |
| Same chunk `41335-41573` | Language substitution and hypothetical-page examples. |

Public primary references:

- [Official launch event](https://www.youtube.com/watch?v=y7koAGLf0EE), Ask segment 11:28.
- [Official 2023 release notes](https://resources.arc.net/hc/en-us/articles/20498377604887-Arc-for-macOS-2023-Release-Notes), Max v1.11.0 and later multi-query/language updates.
- [Official removal entry](https://resources.arc.net/hc/en-us/articles/20498293324823-Arc-for-macOS-2024-2026-Release-Notes), 28 August 2025, v1.110.0.
- [Apple context guidance](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window?changes=_4).
- [Apple response token limit](https://developer.apple.com/documentation/foundationmodels/generationoptions/maximumresponsetokens).

The release notes were checked live. The launch URL could not be fetched by the web tool;
its segment timestamp is also recorded in `reports/ai-online-history.md:7`. Before claiming
visual parity, inspect the actual historical segment in the browser and save reference stills
or a clip. Current Arc cannot demonstrate a feature removed in 2025. The later 1.109 executable recovery
establishes individual layout constraints, typography and animation arguments listed in the
13 November amendment below. It does not establish the complete effective panel geometry,
runtime palette or compositing. Existing Find measurements (300 × 38 pt) are current Cra facts.
Historical/runtime comparisons at 1x and 2x remain mandatory; static constants alone do not
establish visible parity.

## User-visible behavior

| State/action | Required result |
| --- | --- |
| Setting off, unsupported OS, or model unavailable | Existing Find presentation/behavior. No model request or page extraction. |
| Available + opted in, Cmd-F | Top trailing Find or Ask field in the existing child panel; typing still performs normal Find. |
| Matching text, Return / Shift-Return | Existing forward/backward Find. Explicit Ask can ask about a matching phrase. |
| Nonempty text, final zero matches, Return or Ask | Start one question, enter conversation, show loading/streamed answer. Do not infer zero from a pending/nil count. |
| Blank input | No generation. |
| Conversation | User question, quote/excerpt block and concise Markdown answer with bold answer term; follow-up field “Ask a question…”. |
| Follow-up | New answer grounded in this page and bounded previous turns, no second simultaneous turn. |
| Quote Find button | Validate quote against current page, highlight/find and bring it into view; keep conversation open. |
| Unsupported/empty document | “Sorry, I can’t read this type of page.” Ordinary Find remains usable. |
| Quote absent / page changed since answer | “Quote not found. Make sure it’s accurate!” No invented highlight success. |
| Long page / evicted history | Disclose the fraction of readable page retained and show older-messages-hidden indication when applicable. |
| Failure/refusal/unavailable during request | End loading, show concise error, preserve question for retry and usable normal Find. |
| Escape/close | Cancel request, hide panel, clear temporary conversation and return focus through existing Find close path. |

Default Find commands and selection pasteboard behavior stay intact. Shift-Return stays backward
Find outside conversation; conversation Return submits one follow-up. Cmd-F refocuses existing
input. A user can return to normal Find without reopening a new window. Close/turn-off never
silently saves or resumes a request. Quote navigation does not overwrite the user's ordinary
Find query. Unsupported pages are not silently sent to another service.

## Production design and concrete files

| File | Planned responsibility |
| --- | --- |
| New `Packages/CraCore/Sources/CraCore/AskOnPage.swift` | Platform-independent page identity, message/part/state values; eligibility/submit decisions; request identity; transcript bounds; excerpt parsing/validation and quote search state. Keep types feature-specific. |
| New `Packages/CraCore/Sources/CraCore/AskOnPagePrompt.swift` | Historical instruction/example adaptation, tag-safe page context, preferred-language/date parameters, deterministic context fitting/omission, budget accounting, readable-page fraction. No SDK imports. |
| New `Sources/Cra/Services/AskOnPageService.swift` | MainActor session/task owner, injected production extraction/generation closures as needed, FoundationModels streaming adapter and availability checks, cancellation/error mapping. Raw page/question/model text never logged. |
| New `Sources/Cra/Services/BrowserManager+AskOnPage.swift` | Isolated DOM snapshot and quote re-check on a captured runtime; no fetch. Expose minimal production operations through manager; use existing `PageScript.world`/evaluation result conventions. |
| `Sources/Cra/Services/BrowserManager.swift` | Invalidate Ask identity on existing navigation/runtime teardown paths, forward only necessary lifecycle changes; use existing `navigationRevision`. Carry request-correlated final Find state for zero-match submission; no unrelated manager refactor. |
| `Sources/CraCEF/include/CraCEF.h`, `Sources/CraCEF/CraCEF.mm`, `Sources/Cra/Services/WebKit/WebKitBrowser.swift` | Minimal production Find-result correlation/completion seam required for safe zero-match Return, preserving ordinary Find. Forward CEF identifier/finalUpdate and provide equivalent captured-query completion semantics for WebKit; do not change CEF pin or patches. |
| `Sources/Cra/UI/Overlays.swift` | Extend OverlayState and FindBarView callbacks/mode; preserve normal controls/field focus. Keep the existing key-capable FindBarPanel. |
| New `Sources/Cra/UI/AskOnPageConversationView.swift` | AppKit scrollable message/quote views, attributed Markdown subset, follow-up input, quote find/loading/error affordances and accessibility. No web chat renderer/SwiftUI row list. |
| `Sources/Cra/UI/Windows/MainWindowController.swift` | Wire existing Cmd-F/find actions to active page/service, restore Find mode, coordinate focus and page scope, resize existing panel with pinned top/trailing edge. |
| `Sources/Cra/UI/ShellView.swift`, `Sources/Cra/UI/Theme.swift` | One shared preferred panel size and bounded layout for embedded/moved-overlay paths; resize and animation paths consume the same size. Keep status overlay separate. |
| `Packages/CraCore/Sources/CraCore/SidebarModel.swift` | `askOnPage: Bool = false`, missing-key decode false, synthesized coding key/encoding compatibility. |
| `Sources/Cra/UI/Settings/MaxPane.swift` | One Ask on Page row in the existing feature card, existing availability explanation, include flag in master feature array and all-on/off mutation. Match native small illustrations already used. |
| `Packages/CraCore/Sources/CraCore/Sharing.swift` | Add `askOnPage` to **unreportedSettings** so categorization tests pass without transmitting a new setting. |
| `docs/arc-reverse-engineering.md`, `docs/development.md`, `docs/release-checklist.md` | Evidence/limitations, harness entry, checks requiring a real model/display. No unrelated documentation rewrite. |

### Page snapshot, identity and lifecycle

- Extract from the already loaded focused browser, including DOM changes and authenticated
  content. Capture tab UUID, runtime/browser identity, navigationRevision, actual URL, profile
  identity and incognito status before evaluation; check them after every await/callback.
- Prefer one service instance owned by each MainWindowController, containing one current page identity, one active turn/task and bounded visible messages. No global conversation registry, generic request framework, separate lifecycle engine or duplicate pending/task collections are needed.
- Use an isolated-world bounded script to return title, document URL, content type, readable
  text and extraction/truncation metadata. Prefer main/article content then body. Omit
  scripts/styles/SVG/navigation chrome/hidden nodes and form controls; never read password or
  input values. Preserve document order, paragraph boundaries, inline text and Unicode.
  Run bounded traversal/output (initial ceiling 64 KiB text plus capped title/URL), including an explicit visited-node/work ceiling, so huge or mostly-hidden DOMs cannot require an unlimited walk. Do not materialize whole-body innerText/textContent or clone the entire document before applying those bounds. Disclose truncation if the original length is only a
  lower bound. Do not mutate page structure during extraction.
- Allow readable loaded HTML HTTP(S)/file documents; reject internal cra/chrome/devtools pages,
  PDF/plugin documents, no body, failed/empty DOM, inaccessible document and insufficient text.
  Unsupported document policy is pure/tested. Cross-origin frames/closed shadow content are
  not claimed to have been read. Main-frame-only scope is disclosed when relevant.
- One ephemeral conversation belongs to the focused tab/document/profile, not a URL cache.
  A fresh submit rechecks eligibility and current identity. Re-extract on follow-up so dynamic
  page text is current; quotes keep the snapshot text that supported their own turn.
- Cancel and clear on tab switch, focused split change, navigation (including reload to same
  URL and history/pushState revision), profile change, close, runtime replacement, panel close,
  window close, setting off or availability loss. Reopening starts clean. Private tabs follow
  the same ephemeral policy and never share state. No tasks or page snapshots survive teardown.
- Every extraction/model partial/final/error/quote callback carries a request UUID plus page
  identity. A stale callback cannot append a message, reopen/resize the panel, set an error or
  highlight text in another page. Cancellation is both cooperative and guarded on delivery.
- Gate before extraction and again before model submission; observe the existing availability
  status and settings changes. Do not start or continue a hidden background conversation.

### Prompt budget and Apple SDK contract

The installed FoundationModels Swift interface was inspected. `streamResponse(to:options:)`,
`GenerationOptions.maximumResponseTokens` and `GenerationError.exceededContextWindowSize`
exist on macOS 26. `SystemLanguageModel.tokenCount(for:)` requires **26.4**; `contextSize` is
back-deployed and returns 4096. Do not unconditionally call the 26.4 token API from a 26.0 path.

1. Start a fresh `LanguageModelSession` for each turn. Supply fitted prior turns explicitly;
   never let a hidden SDK transcript accumulate independently of the visible history policy.
2. Preserve Arc's research-assistant contract and examples, adapting the model transport only:
   standalone `<excerpt>` citations, concise approximately ten-word next-line answer, bold
   actual answer, mark unsupported guesses, preferred response language, transformations when
   requested. URL/title/current date/body are context; prior dialogue uses explicit roles.
   Page text is untrusted quoted data and cannot replace instructions. Escape context delimiters.
3. Budget against 4096 total tokens. Initial safety target: at most 3072 input tokens, reserving
   768 output tokens plus 256 for framing/uncertainty. These are conservative Cra choices, not
   recovered Arc constants. Count instructions, examples, current question, all retained
   history, page metadata/body and framework framing. The existing string prototype has zero
   schema cost; the pending guided-output amendment below supersedes that transport and
   explicitly budgets nonzero schema cost. It requires a fresh independent plan review.
4. On 26.4+, use actual token counts for the fully assembled instructions/prompt/transcript
   entries and a final fit check; avoid assuming additive counts exactly equal serialized
   framework cost. On 26.0–26.3, use conservative UTF-8-byte accounting plus framing reserve,
   not characters/4. Keep fallback explicitly estimated; Unicode/CJK tests must fit too.
5. Retain current question and instructions first; trim oldest whole completed turn pairs with
   Arc's `[Older messages hidden]` marker, then shorten the readable body to a prefix on a
   paragraph/grapheme boundary. Do not mix a reply with an omitted question or fabricate a
   summary of omitted turns. Bound in-memory turns/text separately (initially 12 pairs and
   64 KiB total transcript); use the same older-history indicator for eviction.
6. Bound question/metadata sizes. If mandatory instructions plus question cannot fit, return a
   concise input-too-long state with the editable question retained; never silently truncate
   the user's question. Calculate disclosure from included readable body/original readable
   body, distinct from token budget utilization and DOM traversal truncation.
7. Stream locally with greedy generation and a 768-token maximum to prevent runaway output.
   The cap can end mid-excerpt without throwing: treat incomplete tags as incomplete, never
   validated citations. Do not claim successful complete output just because iteration ended.
8. On context overflow only, discard the failed partial turn, make one fresh-session retry
   with a smaller body/history budget (e.g. half the page allowance), and update disclosure.
   A second overflow is an error, not an unbounded retry loop. Cancellation/refusal/guardrail/
   unavailable/other failures do not trigger a misleading overflow retry.

### Excerpts, streaming and actual page navigation

- Confirm FoundationModels stream snapshot semantics in the installed SDK. Treat cumulative text snapshots as replacements for the current assistant text, never append each snapshot as a delta. A bounded pure parser of the latest snapshot is preferred over a second incremental-parser state machine; it still handles split tags, repeated/unchanged snapshots, incomplete trailing tags, multiple excerpts, empty/nested/malformed tags, Markdown and literal angle brackets. No raw HTML interpretation.
- Preserve source spelling. Convert only supported Markdown formatting/link labels to quote
  plain text, normalize Unicode canonical form, line endings and runs of whitespace for a
  deterministic substring match against the exact readable source prefix actually supplied for that turn. Retaining a larger extracted document for revalidation does not make unsent text part of the model's disclosed context. No fuzzy matching,
  punctuation deletion or model assertion is enough to validate a quote.
- Keep incomplete/invalid quotations visibly unverified and non-actionable; final unmatched
  excerpts show the recovered not-found warning. A response with no supporting quote must
  identify that it is a guess/background knowledge; do not label it page-supported. Summaries
  and transformations may be multi-line but never manufacture a clickable citation.
- Clicking a validated quote rechecks the same page identity and current live DOM. Through a
  production manager operation, locate the exact normalized text across inline text nodes,
  create/scroll a DOM Range in the isolated evaluator and issue `runtime.browser.findText`
  with the corresponding actual source text using the existing browser Find seam. Native
  find highlight and DOM selection/scroll are tested on the real browser, not just recorded.
- The existing bridge drops CEF `identifier` and `finalUpdate`; a Swift request UUID alone
  cannot identify its old Find callbacks. Do **not** treat generic `didFindMatches` as proof a
  particular quote exists. Quote found/not-found comes from its identity-checked DOM lookup;
  browser find callbacks only maintain normal Find counts outside quote mode. Any normal
  Find action leaves quote navigation mode and restores the ordinary query. Outdated quote
  lookup callbacks cannot issue Find. New ordinary queries reset pending count so Return does
  not turn a stale zero-match result into an Ask request.
- Safe zero-match Return requires a production Find-result correlation/completion seam; it is not optional follow-up work. Resetting count to nil alone cannot prevent an older callback from overwriting it. Forward native CEF `identifier` and `finalUpdate`, and associate delivered state with the active ordinary query/runtime/navigation generation; WebKit captures the query/generation before its asynchronous find/count callbacks. The installed CEF header says the result identifier is unique/incremental for the active search, while its current Find API accepts no caller identifier: establish the association from actual implementation/integration evidence rather than assuming the first callback after a new Swift request belongs to it. Quote-triggered results must never complete an ordinary query. Return may auto-Ask only on a proven final zero for that exact current ordinary query; pending/uncorrelated state never auto-Asks. Explicit Ask remains independently available.
- Before enabling zero-match Return in batch 6, reproduce old-zero/new-matching, old-matching/new-zero, query A→B→A, quote→ordinary-query, find-next, navigation and late-final ordering at this seam and in real CEF. Preserve normal forward/backward Find and quote restoration. Do not guess at identifier semantics, hide ambiguity with delays, or claim the behavior complete without correlation proof. No CEF pin/patch change is authorized.

### Native panel and accessibility

Use the current Find panel and material/theme vocabulary. Expand below the input, retain the
same top/trailing anchor, and clamp height/width to the visible focused page (Library and split
bounds included). An NSScrollView contains reusable/native message and quote views. Render
bold, paragraphs and safe links with attributed text; model HTML is inert. Text is selectable.
Untrusted links must use the existing browser open route and permitted URL policy.

Both ShellView's embedded layout (`findHost`) and MainWindowController's detached page-window
layout (`findPanelFrame`, normal resize and animated resize) consume a single preferred size.
Opening/stream growth must not make an invisible page-sized panel swallow clicks or steal focus
on each token. Return focus to existing browser host logic on close. Bound the panel for small
windows and offscreen pages; do not animate layout repeatedly while scrolling.

Keyboard/AX checks: focused input on Cmd-F, buttons named Ask/Find Quote/Previous/Next/Close,
logical Tab/Shift-Tab order, no keyboard trap, Escape close/cancel, selectable quote/answer,
loading/error status exposed without announcing every token, reduced motion respected.
Use resolved theme and semantic text colors in light/dark/high contrast, and pixel-align at
1x/2x. Screenshot/clip evidence covers hover, loading, quote found/not-found, follow-up, long
page disclosure and panel growth. Historical-unmeasured values remain labelled inference.

## Verification plan

| Layer | Files/checks | Concrete coverage |
| --- | --- | --- |
| Core | New `AskOnPageTests.swift`, `AskOnPagePromptTests.swift` in CraCore tests | Eligibility and pending/zero/matching Return decisions; prompt/metadata delimiters/date/language; full accounting and mandatory-input rejection; CJK/emoji/long body/history; whole-pair eviction; percent/lower-bound disclosure; excerpt chunk splits/malformed tags/Markdown/canonical-whitespace match/false quote; stale identities and cancellation transitions. |
| Settings | `SidebarModelTests.swift`, `ModelFixtureTests.swift`, `MaxMasterSwitchTests.swift`, Model recorded settings fixtures, `SharingTests.swift` | New and missing-key false, round-trip true, older fixture decode/recorded save with false, five-feature mixed/all-on/off state; setting explicitly unreported and no chat/page text in reports. Do not rewrite locked promises. |
| Browser contract | Extend existing `Tests/BrowserManagerLifecycleTests.swift`, `Tests/BrowserManagerSupport/CraCEF.swift`, `Tests/test-browser-manager.sh` only as needed | Production snapshot/quote operations reject malformed/oversized/exception evaluator replies; delayed reply after navigation/reload/runtime/profile/tab change produces no state/highlight; evaluate the captured browser; actual source/result values asserted, not fake call counts alone. |
| Service | New `Tests/AskOnPageServiceTests.swift` and minimal support if existing manager harness is insufficient | Production service with controllable extraction/stream closures: partial/final output, cancellation, opt-out, availability loss, one overflow retry, no retry on refusal, stale stream after close/new request, cleanup and transcript bounds. No sleeps or fake-only bookkeeping assertions. |
| AppKit contract | New `Tests/AskOnPagePanelTests.swift`, `scripts/test-ask-on-page.sh`; wire `scripts/test.sh` and `docs/development.md` | Compile production views, drive input/delegate/actions through real controls, check child-panel size/anchor/clamp, normal Find preserved, quote action/state, tab order, focus token not re-applied per chunk, theme/readability and scaling invariants. Reuse production closures; no test-only window architecture. |
| Local page fixture | New synthetic `Tests/Fixtures/AskOnPage/` HTML pages | Auth-like DOM insertion without fetch, long article, inline quote spans, hidden/chrome/input text exclusion, CJK, repeated quote, changed/removed quote, unsupported content. No real browsing data. |
| Runtime journey | New `Tests/Scenarios/ask-on-page.scenario` where current `cra://debug` CDP/action seams suffice; existing `find-selection` regression | Real CEF loaded DOM extraction, normal search + Enter/Shift-Enter, Ask/control submission, follow-up, quote selection/scroll/highlight, not-found after DOM edit, cancel/navigate/tab/split/profile, close focus, no leaked helper/tasks. Read production UI through accessibility/CDP where appropriate; do not add a separate debug architecture solely for tests. |
| Visual/manual | Historical launch reference vs isolated Cra screenshots/clips; release checklist | Light/dark/themes, 1x/2x, hover/loading/error, actual keyboard, narrow window/Library/splits/devtools child host, animation and screen-reader behavior. Distinguish measured vs inferred historical geometry. |
| Actual model | Apple Intelligence enabled on eligible Mac | Page-supported question, unsupported question, summary, follow-up, large/CJK content and overflow/refusal behavior; inspect actual local answer quality and grounded quotations. |

The existing `CRA_TIDY_FAKE_MODEL` seam can exercise deterministic UI on this Mac while Apple
Intelligence is off. Use a fixture-derived fake response with quote/partial/error coverage and
label every such result **fake model**. A fake run proves wiring and rendering, never actual
FoundationModels quality, grounding or latency. Actual-model acceptance remains explicitly
unverified until run on an enabled model. Do not change the user's system AI setting.

Required checks after root coordinates the shared vendor/build resources: focused Core tests,
new production-file harness, existing browser-manager and Find scenario, `scripts/lint.py`,
`git diff --check`, `scripts/test.sh`, release build and isolated runtime scenario with a fresh
`CRA_DATA_DIR`. Keep profile/data directories separate from daily Cra and other branches.
No full build/test is started by this plan. Coverage gates: changed tested lines >=70%,
CraCore >=85%. Add meaningful mutants/negative cases for new decisions when required; do not
create tests that merely repeat constants or assert a stub was invoked.

## Granular review and commit sequence

Every row is a separately reviewable, subject-only conventional commit. Before **each** commit
and **each** push, an independent Sol reviewer checks behavior/correctness, regressions,
scope and redundant code against the staged diff and tests. Address findings before proceeding.
No self-review substitutes for independent review. No commit or push occurs during planning.

| Batch | Proposed subject | Included evidence/checks before review |
| --- | --- | --- |
| 1 | `feat: model ask on page conversations` | Core contracts/parser/identity and focused tests. |
| 2 | `feat: fit ask on page prompts to local context` | Prompt contract/budget/history/truncation tests; SDK availability verified. |
| 3 | `feat: read ask context from the active page` | Production bounded DOM/quote browser seam, synthetic fixtures, delayed-callback manager contract tests. |
| 4 | `feat: stream ask answers with apple intelligence` | Local service, bounded retry/cancellation/lifecycle tests, no text logging. |
| 5 | `feat: add ask on page to max settings` | Default-off/legacy fixtures/master switch/unreported-setting tests, existing Max styling. |
| 6 | `feat: integrate ask conversations with find` | Minimal proven request-correlated/final Find-result seam, AppKit conversation/input, active-page wiring, all layout paths and ordinary Find/Return/Shift-Return regressions. Zero-match auto-Ask cannot ship ahead of this seam. |
| 7 | `test: verify ask on page browser journeys` | Real-browser fixtures/scenario and focused regression evidence, no unrelated debug additions. |
| 8 | `docs: record ask on page parity evidence` | Measured historical/current visuals, explicit inferred values, verification limitations/checklist. |

Keep tests with their implementation batch whenever they prove that batch; batch 7 adds only
journeys requiring the integrated UI. Adjust batching only to keep every commit compiling and
reviewable; document any scope change first. Before final push: independent Sol review of the
whole branch, required full checks, isolated runtime evidence and an explicit actual-model
verification status. Root owns permission/coordination for publishing.

## Independent review disposition

1. Confirm the proposed Cmd-F/Return/Ask and return-to-Find behavior against historical footage;
   retain the documented fallback only where exact behavior is unavailable.
2. Confirm the deliberately conservative pre-26.4 token fallback and one-retry policy are
   acceptable; neither is a recovered Arc implementation detail.
3. Review quote Range + existing browser Find integration against real Chromium behavior,
   especially pending normal Find callbacks. Do not let ambiguous callback ordering ship.
4. Approve the ephemeral clear-on-focus-switch policy and incomplete historical layout values
   as stated adaptations, with no persistence or background generation.

Independent GPT-6.1 Sol review (2026-11-12): merge with plan fixups applied. Existing user authorization and coordinator review resolve the proposed local token fallback, ephemeral ownership and labelled visual inferences; no additional user approval is requested by these review questions. Historical visual calibration and real CEF callback proof remain implementation acceptance gates, not assumed facts. Full record: `/Users/varunaditya/Desktop/arc-decomp/cra-validation/reviews/plan-askonpage.md`. The reviewed plan-document diff may be committed under coordinator authorization. Each source diff still requires exact-diff independent review. This document marks no feature, test or runtime check complete.

## Reviewed amendment: guided local answers, 12 November 2026

This amendment supersedes the string-response/excerpt-tag transport, snapshot-parser and
schema-zero assumptions above **only after fresh independent approval**. Historical Arc UI,
normal Find, the mandatory CEF final-query correlation gate, page extraction/ownership,
privacy, local-only inference and all unrelated scope constraints remain unchanged.

### Why the transport needs to change

The committed Core and browser-context batches are `c00d0a8` and `30c01a7`. A small per-window
service and actual FoundationModels adapter now exist as an **uncommitted prototype**.
Its controlled provider/manual-clock harness passes 25 checks; 22 focused Core tests pass.
Those checks establish ownership, cumulative replacement, fitted source, bounded text/history,
error/retry/deadline handling and cancellation. They do not establish real model output quality.

Actual on-device generation was run against a synthetic observatory article through the
production string adapter and actual 26.4+ transcript token counter. No browsing data, external
fetch or cloud model was used. The final unchanged string prototype evidence is
`/tmp/cra-askonpage-real-model-final.log`:

| Question | Actual result | Grounding result |
| --- | --- | --- |
| What time does the observatory open? | Correct full source sentence inside standalone excerpt tags; short answer lacked bold emphasis. 676 input tokens. | Exact quote verified. Formatting contract still incomplete. |
| When does it close? | Correct sentence copied with literal `\\n` and escaped slash strings from JSON-quoted history. 731 input tokens. | Citation correctly rejected; no quote action could be enabled. |
| Who founded the observatory? | Correct absence statement, but excerpt tags appeared inline. 790 input tokens. | Citation correctly rejected for invalid structure. |

The initial probe `/tmp/cra-askonpage-real-model-01.log` also produced a shortened quotation
with newly added punctuation; deterministic validation rejected it. Explicit complete-verbatim
sentence guidance and suppression of dialogue headers improved the first turn and are retained
in the prototype. They did not fix follow-up formatting. Probes `-03.log` and `-04.log` preserve
those failures. Readable previous-answer blocks (`-05.log`) still omitted citations; a final
recency reminder (`-06.log`) produced invented dialogue instead of a single answer. Those
ineffective history-format, repeated-format-reminder and slash-encoding changes were removed.
One failed build (`-02.log`) resulted from a test file changing during compilation; it is not
model-quality evidence. None of these runs is reported as a successful real-model feature test.

Do not relax punctuation, accept inline/escaped pseudo-tags, fabricate a source quote, label a
failed output as grounded, or rewrite it with another inference call to conceal these failures.

### Proposed narrow generated shape

Use one feature-specific FoundationModels `@Generable` type in the app, behind the existing
macOS 26 / `canImport` guards:

| Field | Generation guide and native meaning |
| --- | --- |
| `excerpts: [String]` | Zero to four complete, unchanged source quotations. Plain page text only, without XML, Markdown wrappers or JSON escape spelling. Native code bounds each string/array and validates every quote against this turn's exact fitted source. Four is an explicitly chosen local budget bound, not a recovered Arc limit. |
| `answer: String` | Concise plain text, normally one sentence/roughly ten words. Preserve the selected language; summaries/translations/other requested transformations remain allowed. When relying on background knowledge, explicitly say it is a guess or is not on the page. No dialogue or markup. |
| `keyAnswer: String?` | Optional decisive term/value copied exactly from `answer`, for native bold emphasis. Nil/empty is allowed. This is a presentation hint, not evidence of truth or a condition for accepting the answer. |

There is **no model-declared supported/verified flag**. Plain native quote values carry a
validation state computed from exact transmitted-source containment after only canonical
Unicode/whitespace normalization. No fuzzy matching, punctuation deletion or background
knowledge may validate a quote. Invalid quotations remain visibly unverified with the existing
not-found warning; they never gain a Find action. One valid quote does not certify the semantic
truth of every sentence in the answer or of another invalid quote.

The native answer value holds plain answer text, an optional exact substring range for `keyAnswer` and
separate quoted-source values. Render it directly with AppKit attributed text/quote views.
Do not generate excerpt tags/Markdown solely to parse them again. Apply bold only when the
bounded `keyAnswer` is nonempty and occurs verbatim as one contiguous substring in `answer`.
An absent, empty, accent-mismatched or noncontiguous hint leaves the valid answer plain; it
does not reject that answer, its separately validated citations or completed-pair history.
Never accent-fold, fuzzy-match, concatenate answer terms, alter the answer or make another
inference call to repair emphasis. This follows Arc's prompt/Markdown formatting intent;
no recovered native rejection rule for missing bold has been established. While streaming,
answer text may appear before an emphasis hint. Quote controls remain disabled until final
complete-answer/schema validation, independently of whether emphasis is available.

A complete `excerpts: []` is valid for a background guess or other answer without a direct
quotation; it is distinct from an absent/incomplete array in a partial snapshot. An unusable
optional `keyAnswer` is a plain-text presentation fallback, not a final field error. Do not enforce a literal ten-word or
single-line limit on transformations. A multi-line summary/translation can bold a copied
decisive phrase (or the complete answer when no shorter term fits) without narrowing that
existing behavior. Missing/empty actual answer text, incomplete raw/schema output and existing
required-field/resource-bound failures remain errors; optional emphasis does not relax them.

Page-context escaping is a transport representation only. Preserve the actual unescaped
`Fitted.source` prefix for native validation, rendering and later DOM lookup. A source sentence
such as `Budget < €40 & the editor says "use <excerpt> literally".` must remain quotable as
that exact visible text. Literal excerpt-like markers inside typed quote fields are page data,
not parser delimiters. Do not validate against the XML-encoded prompt, render entity spelling
instead of source text, decode arbitrary model escape sequences as a repair, or search the DOM
for the encoded transport string. Verify the same synthetic source end to end, including quotes,
ampersands, angle brackets and marker-like text, without fuzzy quote repair.

When no excerpt validates, the UI must visibly indicate that the answer is not quoted from this
page; this cannot depend on a model support flag. Background guesses remain permitted and must
be identified. This is not a blanket page-only refusal. A requested transformation still runs;
its original-language/source excerpts may accompany the transformed answer. Native evidence
status remains separate from model phrasing. Multiple citations are rendered and validated
individually, and follow-ups retain bounded completed pairs and the same page ownership.

### Native types and removal of superseded code

- Refactor `AskOnPage.Answer` / quote values in CraCore into the small platform-independent
  native result consumed by the service and AppKit. No FoundationModels type enters CraCore.
  Keep exact-source normalization, bounded text, completed-pair history and omission policy.
- Replace the prototype `Generate(Fitted, (String) -> Void)` with a feature-specific typed
  partial update plus one complete result. Keep one current turn/task/deadline per window;
  do not add a transport hierarchy, registry, second parser or parallel raw-answer cache.
- Remove the now-unused `<excerpt>` snapshot scanner, tag-malformed/incomplete parsing branches,
  Markdown-to-plain conversion for citations, markup-derived `Part` cases and parser-only tests.
  Replace them with native quote/value validation and genuinely incomplete typed-field tests.
  Keep adversarial source/punctuation/Unicode, byte bounds and history tests in the new path.
- Remove the prototype's raw assistant-string storage and real-model markup-parser assertions.
  Store bounded native answer/quote values; derive a readable completed-turn history string only
  for the existing fitter. That representation is internal context, never generated transport
  markup that is parsed back into UI. Remove redundant formatting-recovery prompt rules once
  guides carry the output-shape contract. Preserve the original research-assistant behavior and
  historical examples as behavioral evidence, adapting examples into the new fields as needed.
  A turn may enter completed-pair history once its native answer/field/size validation completes,
  including a valid zero-citation background answer or an answer displaying a rejected citation.
  Citation verification controls evidence labels and quote actions individually; it does not
  erase valid unsupported follow-ups or turn the conversation into a page-only refusal. Missing
  complete required fields or interrupted output still cannot enter completed history. Missing
  or unusable optional emphasis alone cannot prevent a complete answer from entering history.
- Core prompt fitting may continue to use a feature-local count closure, whose app adapter knows
  the fixed generated schema. No generic AI/context framework or persistent chat format is added.

### Actual schema cost and complete snapshots

The installed SDK was inspected: `ResponseStream.Snapshot` contains cumulative
`Content.PartiallyGenerated` and `rawContent`; `GeneratedContent.isComplete` and
`Generable.init(_ content:) throws` are available. `GenerationSchema` is Codable. The 26.4+
model provides `tokenCount(for: GenerationSchema)` and `tokenCount(for: transcript entries)`;
transcript prompts accept `responseFormat: .init(type:)`.

1. Count the actual generated schema, including all guides/property descriptions and array
   bounds. On 26.4+, construct the same instruction/prompt transcript with its typed response
   format used for generation. Measure the complete typed request, and independently measure
   the schema; confirm whether schema cost is included by comparing base/typed counts. Use a
   conservative maximum of complete-typed count and base-plus-schema count if serialization
   inclusion is ambiguous. Retain the framing reserve; never count schema as zero or silently
   omit it. No tools are enabled.
2. On 26.0–26.3, include the UTF-8 byte length of the actual encoded Codable generation schema
   in the conservative existing instruction/prompt fallback, plus the framing reserve. Encoding
   failure fails closed. Refit history/page so input plus 768 output plus reserve stays inside
   4096; reject an oversized mandatory request without truncating the user's question.
3. Stream typed cumulative snapshots by replacing current values. Optional fields and array
   elements are provisional, not deltas. Missing actual `answer`, incomplete required arrays or
   partial quote strings must not be promoted to a complete result or actionable citation.
   An optional nil/empty emphasis hint is distinct from an incomplete schema or answer.
4. Iterate one stream once; retain only its latest bounded partial/native value and the final
   bounded raw content needed to construct the full generated type. On stream termination,
   require `rawContent.isComplete`, successful full-type construction and native required-field/
   size validation; compute optional emphasis separately. A token cap may terminate without a thrown error, so incomplete raw
   content is a typed incomplete-answer error. Do not start a second stream/collect pass to
   obtain a final answer. Remove the final raw content after conversion.
5. Preserve current cancellation/identity checks on every partial/final/error. One context
   overflow retry uses a new session and smaller fitted context, discarding prior partial
   values and updating disclosure. Refusal/guardrails, incomplete fields and invalid quotes
   do not start an unbounded or concealed formatting-repair loop.

### Verification and adjusted small commit sequence

| Check | Required evidence |
| --- | --- |
| Native Core values | Exact vs fabricated/punctuation/case/Unicode quotes; multiple valid/invalid quotes; empty/missing/oversized required fields; exact optional emphasis substring range, with nil/empty/accent-mismatched/noncontiguous hints rendering plainly and preserving completed history; no model support flag; completed-pair bounds and source disclosure. Include `<`, `&`, quotes and literal excerpt-like source markers through context escaping, native validation and plain rendering; unsent suffix text remains unverified. |
| SDK-linked controlled service harness | Cumulative field replacement; incomplete arrays/text; final raw incompleteness; late old partial/error after a newer request; opt-out/off-on/model-loss/page change/timeout/owner teardown; history only after a complete validated turn; one overflow retry and no refusal retry. Assert actual native results/state, not only fake call counts. |
| Schema/token budget | Actual schema token count, typed whole-request accounting, escaped maximum metadata/history, older-OS schema-byte fallback, CJK/large page fitting and output-cap incompleteness. Record measured schema count from the same production type. |
| Actual on-device samples | The same synthetic opening-time and follow-up questions must produce exact validated source quotes; record native bold when a usable verbatim hint is present and plain-text fallback otherwise. Add genuinely unsupported background question, multiple-source question, summary, translation and the escaped-representation sentence above. Reproduce French accent-mismatched and noncontiguous multi-fact hints: retain the complete answer/history without repairing either emphasis or citations. Record complete native field values, measured input/schema counts, validation outcomes and failures. No fake-model output certifies this row. |
| Actual DOM representation | Extend the existing real-DOM fixture with visible angle brackets, ampersands, quotation marks and literal excerpt-like markers. Extraction must retain actual visible text, and the later production quote-search/Range seam must find that same unescaped validated source text in the real browser. Do not pass model/transport entity spellings to native Find. |
| Existing gates | Focused Core tests, production browser-context harness and real DOM checks; lint/promises/diff; coordinated native build later. Existing Find correlation/ordinary Find and UI/1x/2x acceptance gates stay mandatory and separate. |

The pending raw-string service prototype is not committed before this amendment review.
After approval, replace its obsolete transport in place and submit one scoped guided-service
commit (`feat(ask): stream grounded native answers`) containing necessary Core native-value/
validation and schema-accounting changes, production adapter/service and focused tests. If
that diff is too large to review safely, split native answer/schema values from their service
consumer, each compiling with meaningful tests; do not commit an unused parallel string
service. Each resulting exact diff still gets independent Sol correctness/redundancy review
before commit and push. Settings, CEF Find-correlation/AppKit UI and runtime journeys follow
as their existing separate batches. No schema implementation starts before this fresh plan
review returns and blocking findings are resolved.

Independent GPT-6.1 Sol amendment review (12 November 2026): ready with the empty-citation,
transformation and history clarifications above. Only the reviewed plan-document diff is
committable at this gate; the frozen raw service prototype is not approved for commit and no
guided source implementation begins until coordinator authorization. Every subsequent exact
source diff still requires independent correctness/redundancy review. Review record:
`/Users/varunaditya/Desktop/arc-decomp/cra-validation/reviews/plan-askonpage-guided-output.md`.

Independent emphasis correction review (12 November 2026): the real French and multi-fact
guided samples exposed a stricter-than-evidence acceptance rule for styling. Optional exact
emphasis with a plain-text fallback is approved as the narrow correction above; citation
grounding, required answer/schema completeness, resource limits and all other gates remain.
Only this plan-document correction is ready for commit, before corresponding source changes.
Review: `/Users/varunaditya/Desktop/arc-decomp/cra-validation/reviews/plan-askonpage-emphasis.md`.


## Reviewed refinement: Find query correlation, 12 November 2026

Independent review accepts the stop/restart design in
`/Users/varunaditya/Desktop/arc-decomp/cra-validation/ask-find-design.md` as a
**conditional source-level design**, with the following implementation and acceptance gates.
This does not establish runtime parity or complete automatic zero-match Ask.

- Use one feature-specific query generation per browser, bound to exact field text, case,
  ordinary/quote purpose, panel lifetime and the existing captured page/runtime identity.
  A→B→A, reopen, owner/page change and quote restoration receive fresh generations.
  Invalidate final-zero eligibility synchronously in the field-edit/programmatic-query path,
  before Observation schedules Find. Capture/check the original page/browser for asynchronous
  Use Selection; its late response must not rewrite another page's query or pasteboard.
- On CEF UI, perform one uninterrupted transaction for every new generation: clear the old
  native tag, `StopFinding(false)`, install the new immutable tag, then call `Find` with the
  existing arguments. Never install the new tag before Stop; a callback during Stop must be
  old/untagged and rejected. No task hop or nested event pump may split this transaction.
  Assert/reject off-UI use or marshal the entire transaction together. Plain Stop invalidates
  first; close retains the existing clear-selection behavior. Same-generation Next/Previous
  calls Find directly, without restarting its session or losing active-match movement.
- Capture generation/purpose at native `OnFindResult` entry, before any dispatch/Task to
  Swift/main. Deliver those immutable captured values with CEF's actual identifier, count,
  ordinal and `finalUpdate`; never read a mutable current tag inside a later delivery closure.
  Reject absent/stale tags and wrong browser/runtime/focused-page identity before mutation.
  The identifier is engine evidence, not a caller ID or proof of ownership by itself.
- This fence relies on the installed CEF `a10dae3408911466b2d90409cc3355cbf6043ffb`
  and Chromium `156.0.8078.96`: UI-thread Find synchronously enters FindTabHelper; Stop marks
  the old session aborted; the next Find records its new session ID before synchronous reply
  reentry; helper filtering rejects older IDs before CEF forwards accepted results. Do not
  guess from the first callback, mirror native counters, await abandoned final replies, add
  delays/queues, or change the CEF pin/patches.
- **Exclusive Find ownership is a release gate.** Inventory and exercise native key/menu,
  Chrome command, extension, page and DevTools routes for the actual runtime styles. Native
  FindBarController can use the same helper independently. Route reachable competing Find
  commands through the app Find path, or synchronously invalidate ownership before they run.
  A foreign higher identifier must never be credited to the current tag. An unobservable
  competing caller blocks auto-Ask completion; report it without silently deleting the
  intended feature. Existing ordinary Find and explicit Ask remain usable.
- WebKit captures generation, query, purpose and WKWebView identity before `web.find`, and
  guards both its native completion and later count-script completion before shared mutation.
  Only the current native `matchFound == false` authorizes zero. The innerText count is a
  display approximation; a positive native result remains positive even when that script
  reports zero/fails. Stop/close invalidates before clearing fields.
- Auto-Ask requires available + opted-in, ordinary purpose, plain Return, nonempty unchanged
  input and a proven final zero for that generation/page. Partial/unknown/negative, quote,
  pending and stale results cannot qualify. Pending Return performs ordinary Find and never
  arms a deferred submission. Shift-Return retains backward Find; explicit Ask/Ctrl-Return
  follows its existing separate contract. Recheck current identity and availability on submit.

| Mandatory verification before batch 6 is complete | Required evidence |
| --- | --- |
| Reordering | Old zero→new matching, old positive→new zero, A→B→C, A→B→A, delayed short queries, partial zero→positive final and close/reopen. Only the exact current generation can update accepted final state. |
| Native delivery boundary | Queue delivery of an already-captured old result, install a new generation, then release delivery. It retains its old tag. Exercise callback reentry during Stop/Find so no old result receives the new tag. |
| Ownership and lifecycle | Production manager rejects wrong runtime/browser and other split/tab/window/profile/private/page generations, including same-URL reload/history and runtime replacement; quote results cannot complete ordinary Find. Enumerate/reroute/invalidate every reachable competing native Find route. |
| Real engines | Controlled real CEF and WKWebView fixtures record synthetic query generation/purpose, actual ID/final/count/ordinal and accepted state. No question/real-page logging. Verify short-query delay, empty/CR-only query, no renderer/cancel, repeated forward/backward wrap, first active match, selection preservation, quote restoration, Use Selection, Jump to Selection, Cmd-F/Cmd-G and Escape. |
| Regression strength | A late-zero test must fail against the old untagged bridge/state. Test actual accepted eligibility/state through production Core/delegate seams, with event/completion synchronization; fake bookkeeping alone cannot certify the native fence. Preserve existing find-selection scenario and ordinary Find when Ask is disabled. |

Keep this in the planned granular Find/UI batch after Settings; each exact implementation
and cleanup diff receives independent review before commit. Before UI completion, settings
opt-out and model-availability loss must synchronously call the window owner's `clear()`
at the mutation/notification source, rather than relying on a later Observation turn.
A production real-store test must turn Ask off then on in the same main-actor turn while
work is pending and prove the old conversation/task cannot survive; test availability loss
and stale extraction/stream delivery equivalently. Service injected-closure tests alone do
not satisfy that integration gate.

Independent plan-only review: approved with these explicit constraints. No source/test changes,
engine runtime check, build, commit or push was performed by this refinement review. Record:
`/Users/varunaditya/Desktop/arc-decomp/cra-validation/reviews/plan-askonpage-find-correlation.md`.


## Proposed upstream reconciliation amendment, 13 November 2026

This section supersedes conflicting earlier implementation/batch instructions. It changes the
plan only and awaits fresh independent review. The coordinator must relay that review and
separately authorize source work before the author merges or implements anything.

### Checked source boundaries and evidence

| Boundary | What was inspected and what remains unproved |
| --- | --- |
| Branch `ea28e0832aa6b8d817c8d224e6fe1e0611748ab7` | B1–B3 bounded extraction/current-document identity/guided service and B4 native Find correlation. Read `reviews/code-askonpage-03.md`, `code-askonpage-04.md` and its follow-up under the external validation directory. Those approvals cover their exact source checkpoints only. |
| Upstream `426c34552a72a1e30da672e42811a90943e190a7` | Existing `AskOnPagePolicy/Prompt/Reply/Tone`, singleton service, `AskOnPageCard.swift` state/controller/view, settings/fixtures, six-feature Max master switch, MainWindowController layout/debug paths and #393/#408 tests/scenarios. Keep this one integrated UI. |
| Merge simulation | Read-only `git merge-tree --write-tree HEAD upstream/main` reports six conflicted paths: Core `AskOnPage.swift`, Core `AskOnPageTests.swift`, app `AskOnPageService.swift`, MainWindowController, `CraCEF.mm`, and `Tests/test-browser-manager.sh`. A clean textual merge elsewhere is not semantic verification. No working-tree merge was performed. |
| Arc 1.109.0 build 67185 | Read `legacy-arc/reports/ask-ui.md`, `ask-logic.md`, `ask-entry-gate.md` and the external `ask-legacy-plan-amendment-recommendations.md`. Thin arm64 executable SHA-256 is `be46bebbf6a14a5b8b8b6381630b4aa3c1acfe5b3ae97312ec6f40608bec1f6c`. These are literal bytes, metadata and machine-code arguments with recovered interpretations, not original Swift source or live backend/pixel evidence. |

All external paths in this amendment are relative to
`/Users/varunaditya/Desktop/arc-decomp/`, except `reviews/`, which means
`/Users/varunaditya/Desktop/arc-decomp/cra-validation/reviews/`.
The coordinator owns the full native build/full suite, app launch, actual-engine/model journeys
and display captures. The amendment author runs none of those and does not change global input,
clipboard, system AI state or display configuration.

### One native card, one per-window conversation owner

Resolve the add/add conflicts by keeping the existing branch native values and guided service
and folding the needed upstream policy/tone helpers into them. Reuse upstream's native
`AskOnPageController`, `AskOnPageState`, `AskOnPageView` and MainWindowController integration.
Do not introduce another card, controller, model adapter, prompt/parser or ownership tree.

| Production file/API | Concrete reconciliation |
| --- | --- |
| Core `AskOnPage.swift` | Retain `AskOnPage` native Draft/Answer/Quote/History/FindRequest/FindState. Add the upstream `AskOnPagePolicy` presentation decisions and retain `AskOnPageTone` with #408 assertions. Remove policy extraction script and quote trimming once all consumers use `AskOnPageContent` and literal native quotes. |
| Core `AskOnPagePrompt.swift` | Keep this branch's single `AskOnPagePrompt`, `Page`, `Fitted`, `fit`, SDK-accounted limits and literal-context construction. Retain needed visible fraction/error wording as small helpers here. Do not retain the upstream second enum, raw `Turn`/dialogue/prompt fitter, server allowance, raw-string fake reply or compatibility wrappers with no production caller. |
| Core tests | Resolve test add/add by retaining branch native ownership/fitting tests and unaffected upstream placeholder/tone/settings checks. Replace only intentionally superseded raw/heuristic promises as specified below. Keep no dead raw parser merely to keep old tests callable. |
| `AskOnPageService.swift` | Keep one instantiable per-window `AskOnPageService` with `ask(_:language:)`, `refresh()`, `clear()`, observable completed `messages`, `current` and `phase`, plus the existing single `AskOnPageLocalModel` adapter. Remove upstream `.shared`, `Page`, `read` and raw `answer` implementation. This is conflict resolution within the same service file, not a parallel replacement service. |
| `AskOnPageController` | Construct exactly one service for the existing window controller, using its BrowserManager, setting closure and current model availability. The card/controller receives that instance. Delete controller `asking`, subject/current tab+URL pairs and raw reply/history storage. Service current/completed messages are the only question/answer/source history. |
| `AskOnPageState` / view | Keep enabled/canAsk/tone/height and quote-navigation presentation state. Observe the same service directly; derive conversation state from completed messages or its current message. Render native answer/excerpts and optional literal emphasis directly. No native-to-Markdown-to-parser conversion and no second copied message array. |
| MainWindowController | Keep upstream's existing card hosting, tone, resize, debug and settings entry points. Replace `AskOnPageService.shared` calls and tab+URL refresh with that same per-window service and captured BrowserManager context. Keep B4 correlated Find delegate/state and query invalidation. Remove upstream `lastFindText`, `findCountText` and generic `matchesUpdated` association after migration. Fold the harmless double `prepareFind` into visible-find versus hidden-prepare branches only while touching this path. |
| CEF/WebKit/harness conflicts | Retain B4 generation/purpose capture, UI-thread guards, real identifier/finalUpdate, Stop-before-tag ordering and native-false WebKit zero rule. Preserve unrelated upstream changes and include every required production support file once in the harness script. A merged compile cannot certify native ordering. |
| Settings/Max/sharing | Use upstream's existing opt-in field/row, defaults, fixtures and six-feature master switch, including Instant Links. Do not re-add the former five-feature implementation or change upstream's sharing classification, settings format or unrelated feature behavior. |
| Debug/scenarios | Adapt existing upstream Ask readouts/quote commands to native fields and bounded messages. Keep diagnostics synthetic and avoid page/question/answer text logging. Keep the existing dark-card scenario and its #408 behavior. Deterministic fake-model generation, if needed for that existing journey, returns native typed fields through the existing injected generation seam; it does not restore a raw fake parser path. |

The current upstream one-off SwiftUI hosting tree remains the starting implementation. The
older plan to add a separate AppKit conversation/NSScrollView is superseded. Use the existing
native input/control seams for the required keyboard/focus behavior, without an unrelated UI
technology rewrite or a new motion framework.

### Entry, page eligibility and Find behavior

Choose the recovered legacy page restrictions for the user-facing Ask eligibility. This is an
intentional change from the earlier branch plan and upstream's HTTP(S)/file predicate.
Ordinary Find remains available on every page it already supports.

| Decision | Exact contract and minimal API choice |
| --- | --- |
| Global enablement | Existing local opt-in AND current local model availability replace Arc's remote flag AND preference. Do not add a remote flag, cloud account or network request. Off/unavailable shows ordinary Find and never extracts/generates. |
| Combined surface | When enabled, retain upstream's combined card even if Ask is ineligible. `isValidAskPage` controls Ask only; it does not force the disabled-feature native Find factory. Exact placeholders are `Find in page…`, `Find or ask…`, then `Ask a question…`. |
| Pure eligibility | Extend the existing `AskOnPagePolicy.canAsk` to accept URL, incognito and resolved document-kind evidence, with no permissive private default. Allow HTTP(S) in a normal non-incognito browsing context; exclude exact `search.arc.net`, PDF, image and movie types. `AskOnPageContent.supportsURL` delegates URL restrictions to this policy instead of keeping a second scheme predicate. |
| Type evidence | Resolve available browser MIME/document kind through AppKit-side `UTType` conformance, with URL content/resource type and filename-extension fallback where available. Pass only pure classification to Core. Use current document evidence rather than a suffix-only assertion. Unknown type can pass this preliminary gate as in Arc, but the existing bounded snapshot decoder still requires actual HTML/XHTML before generation. No URL refetch, synchronous remote resource lookup or unrelated type infrastructure. |
| Captured identity | `askOnPageContext` rejects private/ineligible pages before extraction, while `findPageContext` still supports ordinary Find there. Retain runtime, tab, focus/navigation revision, actual URL, profile and incognito identity at every callback. Reload/same-URL history/runtime replacement remain invalidating changes. Recheck content type and identity after extraction and before generation. |
| Initial plain Return | Change `AskOnPagePolicy.returnKey` to receive proven final-zero eligibility from `AskOnPage.FindState`, plus forward/backward intent, rather than guessing from an optional display count. Ask only for unchanged nonblank ordinary input and exact-generation final zero. Pending/nil/partial/negative/stale/quote results perform ordinary Find; they never arm deferred Ask. Explicit Ask remains available for valid nonblank input independent of match count. |
| Conversation Return | Plain Return submits one nonblank follow-up through the same service, which rejects a second simultaneous request. Follow-up re-extracts this same current document and uses bounded complete pairs. Blank-follow-up rejection is the approved local adaptation; legacy canAsk alone did not establish it. |
| Keyboard | Down/Up and Shift-Return call next/previous Find, including in conversation; they never submit Ask. Cmd-G/Shift-Cmd-G retain their existing Find actions. Cmd-F refocuses/selects the existing field through the actual native editor/responder path, without reset or submit. Tab/Shift-Tab and Escape retain usable focus/close behavior. Do not infer unimplemented modifier submits from the legacy enum alone. |
| Quote navigation | A `Find on Page` action keeps the conversation open. It searches the native quote's plain text, with no punctuation stripping, sentence/eight-word fallback, Markdown reparsing or generic count-as-found claim. Navigation within the page preserves conversation; an actual captured document/ownership change clears it. |

Add deterministic Core tables for valid HTTP/HTTPS, exact host exclusion, file/internal schemes,
incognito, resolved PDF/image/movie, unknown kind and HTML. Test filename/content-type mismatch
and the guarded actual HTML check. Move the deterministic browser fixture to local HTTP for
eligible Ask journeys; retain explicit file/private denial cases. A file-loaded fixture must
not be counted as a successful eligible Ask test after this change.

For quotes, extend the existing BrowserManager Ask extension with one operation
`findAskOnPageQuote(_:in:request:completion:)`, taking literal quote text, captured
`AskOnPageContext` and the quote-purpose `AskOnPage.FindRequest` returned by existing
`prepareFind`. This reuses B4's request generation rather than adding a second token registry.
It performs bounded normalized live-DOM text lookup across inline nodes. The lookup is read-only;
before issuing Range/scroll/native highlight effects, recheck both the current context and
`findState.request` against the captured request. Existing
`BrowserManager.find(... purpose: .quote)` then uses that same generation. Its Boolean
completion describes that exact DOM lookup, not a generic Find callback. The controller
accepts a completed service message ID and quote index, refreshes/checks the same service's
current page ownership, and permits only that specific native verified quote. A newer quote,
ordinary Find, close or owner change invalidates the captured generation. Reject stale/retired
quote callbacks before any highlight or presentation mutation; prove this with actual delayed
DOM delivery and effect tests. Key quote presentation by message ID and quote index, not shared
raw text. Remove upstream quote candidates, pending raw quote, DispatchWorkItem timeout and
count-based retry path together.

Keep `overlay.findQuery` as the ordinary/follow-up input. Quote navigation does not overwrite
it. The next ordinary query/next/previous action exits quote purpose and starts/restores the
ordinary generation as needed. Repeated same-generation next/previous retain native active
match/selection and wrap behavior. Use Selection captures/rechecks the original browser/page
before changing the field or find pasteboard. Closing follows existing selection/focus policy
and calls the same service's `clear()`.

### Synchronous invalidation is mandatory

Observation is a sustained-state backstop. It cannot detect a same-main-actor off/on edge that
coalesces before observation delivery. A final value check is insufficient.

Use the existing NotificationCenter mechanism with feature-specific notifications, without a
new owner registry. In `SidebarStore.settings.didSet`, when Ask transitions true to false,
synchronously post the Ask-disable event for that store before the setter returns. Preserve
existing persistence and unrelated setting effects. At the actual `TidyTabsService.status`
write boundary, when model availability becomes false, synchronously post the matching
unavailability event. All production status writes, including refresh, must cross that hook.
Each per-window owner registers a weak synchronous main-actor callback with no dispatch/Task
hop, filters the settings event to its store, and calls its own service `clear()` immediately.
Remove observer tokens on teardown. Never instantiate a second service from a notification.
A later same-turn enable/available write starts clean. Existing refresh/Observation remains a
backstop; it does not replace either mutation hook.

Page/runtime/focus/profile/private invalidation also calls `refresh` or `clear` from existing
actual mutation paths, before a replacement owner can accept work. The callback guards remain
necessary for providers that ignore cancellation. Do not rely solely on a later UI refresh or
current Boolean equality to prove these transitions were seen.

The required regression compiles the production SidebarStore and window-owned service path:
start pending extraction or a cancellation-ignoring stream, set the real store Ask off then on
in one main-actor turn, release the old delivery, and assert old current/completed content is
absent and a new request remains correct. Cover two window owners of that store, model-loss
write hooks, window teardown and late extraction/partial/final/error. Existing closure-only
service regressions are useful but cannot certify this integration. Recreate the missing-hook
version and show this real-store test fails before fixing it.

### Historical request behavior and the approved local adaptation

| Exact legacy fact | Cra decision |
| --- | --- |
| Shared budget `max(1, roundTiesAway(clientLimit * 0.8) - 50)` | FRINTA is ties away from zero, not truncation. This corrects the older 1.171 interpretation too. Record it as historical behavior; do not substitute it for Apple's shared context contract. |
| Initial target `3 * min(budget, 16000) - (instructions.count + examples.count + 200)` | Swift character counts and post-prefix ellipsis explain legacy page fractions. Keep local bounded extraction, actual schema/typed request accounting and 4096 total / 768 output / 256 framing reserves. Never import a server 16k allowance into the local model. |
| First grounding user part is nonomittable, priority 999; later lower-priority history can omit | Keep explicit complete-pair history bounds/eviction and older-message disclosure. Do not keep raw upstream turns/history beside native service messages. |
| First question appears in joined grounding text and serializer suffix | Preserve this established static oddity in the research account. Include the current question once in Cra's approved local request. |
| Literal URL fragment closes with `</title>`; privacy example is malformed Markdown | Preserve original bytes as evidence. Keep the approved literal-page fence/escaped metadata and typed fields, without adding malformed templates to the local request. |
| Raw lowercase excerpt splitter publishes open-tag quote parts during streaming | Keep guided fields in production schema order `excerpts`, `answer`, optional `keyAnswer`. Replace cumulative snapshots; require complete raw SDK content/full native construction for final acceptance. No raw echo cleanup/tag parser or formatting-repair generation. |
| Guess disclosure, transformations, concise answer and bold term | Keep these semantics. A missing/unusable optional literal emphasis hint renders the unchanged plain answer. Empty or rejected citations do not alone invalidate an otherwise complete answer/history. A source-present quote proves textual presence, not semantic support. |

Retain the already-reviewed one-overflow retry, current-request guards, per-turn fitted-source
validation, output cap, older-OS schema-byte fallback and newer typed/schema token measurement.
Partial quotations remain unverified/non-actionable. No resource/validation weakening is
justified by legacy's permissive parser. Preserve the actual-model failures recorded by B3,
including unrelated source-present quotes on a background answer and the literal-symbol
full-sentence probe failure. Later actual-model acceptance must report their disposition.
A fake-model journey proves deterministic wiring, never model quality or historical pixels.

### Shipped promises and granular source sequence after approval

The user-authorized fidelity reconciliation deliberately replaces #393 pending multiword
Ask, raw prompt/tag parser/echo cleanup and shortened-quote transport expectations. This is a
named shipped-behavior change, not an accidental conflict resolution. Keep unaffected #393
placeholders, ordinary matching Find, explicit Ask/follow-up, visible quote action/disclosure
and scenario coverage. Retain every #408 tone assertion and its dark-card scenario unchanged
in behavior. Keep all unrelated upstream promises and features.

For each intentionally changed #393 test/scenario, list the old/new contract in its commit,
retain relevant `.bug` / promise tags on replacement coverage, run
`scripts/promises.py --update`, and inspect that only those intended entries change.
Name `#393` in the commit subject whenever changing its locked behavior. Do not bulk refresh
the lock or delete required behavior to obtain a passing check. The user has authorized the
fidelity change; the review gate does not require asking again for that decision.

| Batch | Small compiling boundary and proposed subject | Required review evidence |
| --- | --- | --- |
| R0 | Plan only, `docs(ask): reconcile upstream and legacy contracts` | Independent review of this exact amended document and external handoff. No source/merge/commit until coordinator relay/authorization. |
| R1 | Upstream reconciliation, `fix(ask): reconcile native ownership for #393` | Resolve the six conflicts, adapt existing card/controller directly to the one service/native fields, merge policy/tone and only required native fake/debug consumers, retain B4 and unrelated upstream. Include necessary #393 replacements/lock updates and focused Core/service/manager checks. This minimum compile-preserving integration is one review boundary; split only if each smaller boundary compiles and leaves no unused parallel implementation. |
| R2 | Eligibility and synchronous lifecycle, `fix(ask): enforce document and disable ownership for #393` | Legacy policy and HTTP fixture; actual store/status mutation hooks; real-store same-turn/two-window cancellation-ignoring regressions, page/profile/private transitions and existing defaults/master-switch tests. Put the defect back and record the regression failure. |
| R3 | Quote/keyboard/layout fidelity, `fix(ask): match native find and quote behavior for #393` | One bounded live-DOM quote/Range operation, exact-source native highlight, restored ordinary Find, native keyboard/focus paths and measured legacy constraints below. Remove migrated fallback code in this same batch. Production control/layout harness and existing/new HTTP journeys; no parser/second controller. |
| R4 | Integrated evidence, `test(ask): verify reconciled browser journeys` | Coordinator-owned actual CEF/WebKit adversarial/native-ownership gates, ordinary find-selection, same-document Range/selection/scroll, window/split/profile/lifecycle, #408 appearance and actual local-model samples. Tests stay with R1–R3 where possible; this adds only integrated journeys/evidence. |
| R5 | Final parity record, `docs(ask): record reconciled validation` | Current source/build/runtime/model/display evidence with remaining limitations and release checklist/clip. Independent whole-branch review plus root-coordinated full suite/build before final publication. |

Each exact source diff receives independent Sol correctness/regression/redundancy review after
focused meaningful checks and before commit/push. Existing B3/B4 approval does not transfer to
merged changes. Use isolated scratch paths and `--jobs 2` for focused Swift checks. Root owns
shared full build/test/runtime/display resources; no author app launch or global input.

### Concrete UI constraints and acceptance gates

| Legacy executable constraint | Apply to the existing upstream card |
| --- | --- |
| Content max width 400; conversation max width 400 and max height 450 | Treat these as maxima. Input/outer layout add height. Clamp the same preferred size to the visible focused page on embedded/detached, resize/animated, Library/split/DevTools paths. Do not fix total panel size at 400×450 or retain a page-sized input-blocking panel. |
| Shared conversation spacing 18 | Replace current upstream 24 with the recovered 18 in this path. |
| Input first-text-baseline row, spacing 8; all-edge padding 12 plus leading 6 | Use these constraints, with system medium 16 before conversation and 14 during it. Keep rounded system medium 13 for count/no-match and dynamic callout semibold Ask label. |
| Radius 10 outer; conversation input radius 4/padding 6; close radius 6/top-trailing padding 9 | Reuse the existing card construction and controls. Shared unresolved material/stroke/shadow values remain inferred. |
| Quote leading rule 2 at primary opacity .1; body text primary opacity .8 | Use plain selectable quote text. `Find on Page` plus `arrow.forward`, 11 bold and 4 top padding. Preserve loading/found/notFound states and exact warning `Quote not found. Make sure it’s accurate!`; legacy error is red. No quote collapse interaction. |
| Spring .4/.75/.1; conversation easeInOut; pulse easeInOut .8 autoreverse; quote hover timingCurve(.25,.1,.25,1) .2 | Apply through existing UI technology and respect reduced motion. Static arguments do not prove runtime motion parity. |
| Palette is unresolved at runtime | Keep upstream #408 tone, effective card appearance and contrast behavior from measured capture. A static `legacyColorScheme` helper does not prove the view's effective runtime palette. Do not replace #408 with inferred dark/light values. |

| Gate before complete-feature acceptance | Concrete required evidence |
| --- | --- |
| Native Find fence | Real pinned CEF Stop(false)/tag/Find transaction and callback-entry capture under reentry and delayed delivery; actual identifiers/final/count/ordinal, A/B/C and A/B/A, old zero/new positive and inverse, partial zero/final positive or negative, short/empty/CR-only query, no renderer/cancel, close/reopen, runtime/reload/history/focus/split/window/profile changes. SDK/source tests do not certify engine behavior. |
| Exclusive Find ownership | Inventory and exercise native key/menu/Chrome commands, extensions including chrome.find if exposed, page window.find and DevTools frontend/target search. Route competitors through app Find or synchronously invalidate ownership. Intercepting three command IDs is not proof of exclusivity. An unobservable competitor blocks auto-Ask completion and must be reported, without deleting intended functionality to hide the blocker. |
| Actual WebKit | Native false alone authorizes zero; test delayed native completion/script count, positive native with zero/failing script/iframe count, next/previous ordinal/selection/wrap and stale query/owner rejection. |
| Lifecycle | Actual settings off/on in one actor turn and model availability write loss clear every window owner synchronously. Late extraction/partial/final/error/quote deliveries cannot revive or resize old state. Real profile/private mutation paths, close/deinit and new request are covered. |
| Quotes and ordinary Find | Actual HTTP DOM spans with angle brackets, ampersands, quotes, literal excerpt-like markers, Unicode, repeated/removed/mutated quotes. DOM lookup and native Range/scroll/highlight use the same literal validated text. Conversation persists during quote navigation; ordinary query is restored and actual document change clears it. Preserve Use Selection, Jump to Selection, Cmd-F/Cmd-G, Down/Up, Return/Shift-Return and Escape. |
| Visual and tone | Historical/reference and isolated Cra captures on same display at 1x/2x, dark/light including light space on dark Mac, hover/loading/quote errors, growth/450 cap/narrow clamp, focus and reduced motion. Keep #408 readout/scenario and inspect actual pixels/effective appearance. Record unresolved compositing separately. |
| Model and final checks | Actual typed on-device opening/follow-up, unsupported background, summary/translation/multiple-source/literal-symbol/CJK/large-context samples with native fields/schema/input counts and explicit failures. Focused tests/lint/promises/diff, coordinator full suite/build and whole-branch review. Fake samples, successful compilation or HTTP responses alone cannot close runtime/visual/model gates. |

Status at the original R0 author amendment: documentation only; no source/merge/runtime action
had occurred. The current reviewed implementation and open acceptance gates are recorded at
the top of this plan and in [Ask validation](../ask-on-page-validation.md).
