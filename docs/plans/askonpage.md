# Ask on Page implementation plan

Status: independently reviewed with required Find-result, bounded extraction and stream-ownership clarifications below. Coordinator may authorize implementation; this plan alone authorizes no implementation or commit.
Branch: `askonpage`, base `fccc893`.
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
or a clip. Current Arc cannot demonstrate a feature removed in 2025. No exact Ask panel width,
height, duration or easing has been established. Existing Find measurements (300 × 38 pt) are
current Cra facts, not evidence of historical Ask dimensions. Conversation layout values below
are implementation choices to be calibrated against historical footage, and must be labelled
as inferred if footage cannot resolve them. Static metadata establishes state, not pixels.

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
   history, page metadata/body and framework framing. String streaming uses no Generable
   response schema; therefore schema/tool token cost is zero. Adding one later requires its
   budget and a fresh plan review.
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
