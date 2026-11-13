# 5-Second Previews implementation plan

Status, 13 November 2026: B1–B7 implementation independently reviewed and committed; current native build and full suite pass. Whole-feature acceptance and B8 documentation approval remain **PENDING** the bounded native/manual observations below. This documentation draft adds no source behavior and claims no new runtime pass.

Branch: `5secondpreviews`, base `fccc893ca3989ebed0485dd9a67622fa7950f0c9`.
Worktree: `/Users/varunaditya/.codex/worktrees/cra-5secondpreviews/cra`.

## Scope and review gates

Implement Arc's existing 5-Second Previews UI and logic with on-device Apple Intelligence. Repair the preview-specific lifecycle, isolation and fetching gaps. Preserve unrelated features, user edits, data formats and other branches. No cloud inference, new settings, telemetry, release-pipeline changes, CEF pin changes, commits or pushes without the user's existing authorization.

1. Independently review this complete plan before any source edits. Record reviewer, verdict, requested changes and their disposition here. A plan-changing discovery returns to this gate.
2. Work in the small batches below. Write each regression first and observe its failure, then implement the fix and run the focused checks.
3. Before **every** commit, obtain an independent Sol review of that exact diff, tests and unnecessary/redundant code. Address findings and obtain re-review when the diff changes materially. No self-review substitute.
4. Each commit uses a granular conventional subject only. No commit body. Do not push.
5. Coordinate full builds/tests/runtime launches with the root agent; shared CEF vendor files and machine resources must not race. Targeted package tests may use a separate scratch directory.

Read: `CLAUDE.md`, `CONTRIBUTING.md`, `docs/development.md`, `docs/testing.md`, `docs/reviewing.md`, existing preview production code and tests. No skills used.

## Evidence and boundaries

| Evidence | What it establishes |
| --- | --- |
| `docs/arc-reverse-engineering.md:3869–3915` | Arc 1.171 measured hover triggers, card geometry, streaming, motion and sharing. Preserve these measurements and the existing native UI. |
| `/Users/varunaditya/Desktop/arc-decomp/CRA_COMPARISON.md:19–24,33–39` | Near-verbatim preview instructions; required-summary/query differences; URL-only caches; unrestricted fetches; transient negative caching and context gaps. |
| `/Users/varunaditya/Desktop/arc-decomp/AI_FEATURES.md:14,25` | Structured answer-card behavior. The product name does not specify a five-second network timeout. |
| `/Users/varunaditya/Desktop/arc-decomp/reports/ai-bundle-evidence.md:141–161` | Separate snapshot/summary tasks; browser-context cache key; localized streaming; blocked/no-content/timeout state. Exact cache duration is unknown. |
| `/Users/varunaditya/Desktop/arc-decomp/reports/ai-pipeline-evidence.md:26–38` | Snapshot text threshold greater than 49; optional search-derived one-word focus; title/URL/body/language; structured streaming. |
| `/Users/varunaditya/Desktop/arc-decomp/inventory/ai/feature-prompts.json` | Literal `quickSummary: string?` and `userQuestion: string? // 1-word question ... based on user's search query` schema fragments. |

The current source already implements and tests much of the measured UI. Existing documentation's blanket claim of parity is not proof of the audited lifecycle or real-model quality. Unknown Arc timeout/cache parameters will be identified as Cra choices, never claimed as recovered values. Regex HTML extraction is not a JavaScript-rendered snapshot; keep that limitation explicit.

Retained documented adaptations: Apple Intelligence replaces Arc's cloud model; Cra attribution and existing emoji mapping replace Arc branding; previews remain off by default, unavailable when AI is unavailable, suppressed for incognito, constrained to public web URLs and HTTPS-only settings. Resource budgets and retry limits below are local-model/hover protections. No newly invented visual deviations. Restore optional quick summary and search-focus semantics where the recovered schema establishes them.

## Acceptance contract: UI stays faithful

| State | Required behavior |
| --- | --- |
| Entry | Existing Max toggle and availability gating. No request before the one-second rested hover and successful page inspection. |
| Automatic sites | Arc's Google, X/Twitter and Hacker News selectors only. HN comments and Google side-panel links do not auto-open. |
| Shift | Sampled on pointer entry. Pressing Shift later does not open a card. Same-site link gets the small title/address card; cross-site gets the summary. |
| Loading | Existing 300 × 52 pt card, two grey bars. Loading always ends on success or terminal error; it cannot remain spinning forever after HTML/model failure. |
| Summary | 300 pt wide; 12 pt corners; optional 100 pt banner; 13 pt bold quick summary when present; 2–4 final details, SF Symbols, existing spacing, colors and row fades. Progressive rows may be incomplete while streaming. |
| Placement/motion | Preserve 6 pt vertical gap, 7 pt left offset, top-anchored growth, above-link fallback, 0.25 s opening and 0.14 s closing. Leaving closes unless pointer is on the card. |
| Empty/failure | Existing “No preview available” state. A transient failure is retryable on the next hover. No new error panel, retry button or wording. |
| Share | Existing Copy as Text, Copy as Image and system share menu. Share only a current completed usable result; no stale image/result/favicons when a reused card changes identity. |
| Accessibility/focus | Preserve non-key/non-main card and native interaction. Light/dark, themes, 1x/2x and multiple displays remain valid. |

Existing `LinkSummaryCardLayout`, sharing layout and drawing stay unchanged unless a reproduced feature regression requires a precise change. Preserve existing panel/share tests.

## Approved implementation design

The following design and regression matrix preserve the reviewed implementation plan. They are historical requirements, not a list of newly unimplemented source tasks. Current dispositions and evidence appear below.

### 1. Identity, isolation and cache outcomes

- Add a pure, hashable preview request key in CraCore. Include effective profile identity (explicit Default for nil), original link, effective HTTPS fetch URL/policy, search context and resolved output language. Capture language once per request; cache lookup and generation use the same value.
- Use typed identity for summary, title and image caches. A single full key for all three is acceptable and safest; no broader cache alias that can share profile-authenticated metadata. Bound caches to current capacities (40 cards/titles, 20 images) and keep them memory-only.
- Preserve original link for card display/sharing. Use returned validated final page URL for relative metadata/image resolution. Do not alias redirect cache entries across contexts.
- Replace `LinkSummaryResult??`'s overloaded outcome semantics with explicit successful/blocked/no-content/transient/cancelled outcomes at the production seam. Cache successful completed results. Do **not** cache transient network/model/refusal/context errors, cancellation or partial streams.
- Simplest negative-cache policy: do not cache blocked/no-content results either. Show the current terminal empty state and re-evaluate on the next hover. This prevents a login/security challenge becoming permanently sticky and avoids an invented Arc TTL. No clock or persistent-cache migration is needed.

### 2. Request generations and owned work

- Model each entered hover/presentation as a fresh generation independent of URL. Identity includes originating window/tab/runtime, page/search context, profile, HTTPS policy and language. Theme/favicon may update without creating cross-context reuse.
- Pass the existing tab/runtime identity from `MainWindowController`; compare context, not only URL, when deciding a repeated status update can be ignored. Keep Shift sampled on entry for the same unchanged hover.
- Guard resting completion, inspection callback, title return, every streamed result and image update using the captured generation and current presentation identity. An A→B→A hover cannot accept A's first callback.
- Carry the inspected `href` back from the existing hover script and compare it with the requested link before opening; the current bridge drops it. Bind inspection to the original runtime/page so navigation/reuse cannot open an old link.
- Cancel on stop, window/tab/page/context changes, feature-off/availability loss and hide. Pointer entering the card preserves that presentation only for an ordinary pointer transfer; a setting/availability/origin-context invalidation is a hard stop even while the pointer is on the card. The current `linkHoverChanged(nil)` pointer exception cannot be used as the sole opt-out path. Ensure profile/page changes invalidate even if the next status string is the same URL.
- Keep orchestration to one presentation generation and its owned loading operation; no parallel request engine, generic lifecycle framework or cache coordinator. Own HTML/model/image work under the loading operation. Track and cancel the image child; do not launch an untracked `Task`. Do not let image completion mutate caches or publish after cancellation/generation replacement. Keep image arrival after final summary working while the presentation remains active. Publish summary completion without waiting for the optional image; keep the bounded image child attached to the same cancellable operation until it ends, rather than detaching it when the summary finishes.
- A retry discards old partial output before publishing new partials. A terminal blocked/error result clears stale partial rows and disables share.

### 3. Dedicated bounded preview transport

Keep generic `fetchURL` and restricted `fetchPluginURL` behavior and signatures intact. They serve live folders/plugins and are not preview infrastructure.

- Add a dedicated preview HTML **single-hop** bridge method in `CraCEF.h`/`.mm`, returning a cancellable request handle. Its operation owns profile readiness waiting, CEF request, byte accumulation, timeout, completion and cancellation state.
- Always use `UR_FLAG_STOP_ON_REDIRECT`, the selected profile's existing credentials, GET and the HTML Accept header. Profile readiness is part of the deadline. Cancelling before readiness must prevent later request creation.
- Cap HTML before appending bytes (initial proposal: 1 MiB response bytes, separate from the existing 400,000-character extraction cap). Oversized body, timeout and cancellation release the request/body promptly and finish exactly once. Retain no completed CEF request for a delayed timeout closure. Existing plugin cap/timer stays unchanged.
- Initial policy: 20 seconds for the whole page fetch including readiness and all hops; at most five redirects. These are Cra resource limits, not Arc measurements. Use a scheduler/injected clock for Swift policy tests; bridge timer is explicitly cancelled/invalidated on completion.
- Swift preview transport owns the redirect loop. Validate initial URL and **each** resolved Location before issuing another request. Enforce HTTP(S), existing public-host policy, HTTPS-only upgrade and hop/loop bounds. Reject missing/invalid Location and invalid final URL; preserve MIME/status and final URL explicitly. Validating only after an automatic redirect is insufficient.
- Reject private/local targets, credential-bearing URLs and non-web schemes before following. Use URL parsing/canonical host representations rather than substring checks. Preserve authenticated requests within the selected profile without copying one hop's Authorization header to another host.
- A cancellation handler bridges Swift cancellation to the request handle on the proper CEF/main thread; guard cancellation-vs-completion races, including synchronous creation failure. Resume the continuation exactly once.
- Images remain cookie-free and ephemeral. Replace automatic redirect-following `data(for:)` with an owned, cancellable bounded URLSession delegate operation (or equivalent existing production seam). Validate every image redirect before following; enforce the existing 4 MB cap **while receiving**, an aggregate 8-second deadline, status/MIME validation and final URL validation. A missing/failed image does not fail a usable summary.
- No DNS firewall claim: existing public-host URL policy does not prove protection from a public hostname resolving to private addresses or DNS rebinding. Document this existing boundary honestly; do not expand this feature into an unrelated network stack rewrite.

### 4. Local prompt, schema and fitting

- Keep the two recovered instruction sentences verbatim as trusted session instructions. Page text, title, description, URL and query stay request data. Do not add tools or remote fallback.
- Make guided `quickSummary` optional as Arc's schema specifies. Keep 2–4 final details and current label/icon/info guides. Adapt partially generated fields without treating absent optional summary as failure.
- Reproduce the recovered optional `userQuestion` one-word focus semantics when search context is present; feed the original bounded query as request data. It informs the same single model generation and is not displayed. The raw builder conditionally inserts this optional output-field guide before quickSummary; do not turn it into an input requiring a second model. Prefer one static optional guided field with nil/no-focus instructions for queryless requests, documenting that schema adaptation, over dynamically rebuilding schemas or duplicating the whole response type per query. Verify exact builder fragments before finalizing the guided shape.
- Preserve query parsing and preferred-language resolution. Include query/language in request identity. Do not require English-only output or truncate all languages by English word-count rules.
- Add a pure preview prompt-fitting policy covering **all** variable data: URL, title, description, body, query and language, plus wrapper overhead. Explicitly reserve room for trusted instructions, generated schema and the answer. Verify installed SDK capabilities before choosing actual token-count APIs.
- Start with a conservative combined variable/wrapper UTF-8 budget (proposal: 1,536 bytes), reserving approximately 1,536 tokens for instructions/schema and 1,024 for output within the local 4,096-token context. This is a conservative heuristic, not exact token accounting. Check fixed schema overhead and tune with real-model evidence; preserve useful title/query/body allocation rather than letting one giant field consume everything.
- Unicode-safe fitting: oversized metadata/URLs/query, CJK, combining characters and emoji cannot bypass the total budget. Preserve delimiters and instructions, shrink data only, and retain the actual URL outside the prompt for navigation/share.
- On the SDK's specifically classified context-window overflow, retry **once** in a fresh session with a substantially smaller total payload (half budget). Reset streamed partials before retry. Do not retry cancellation, safety refusal, unsupported language, model unavailability or generic errors. No unbounded retry or broad exception-string matching.
- Bound the model/fitting phase with a feature-local summary deadline through the existing Scheduler, including the single overflow retry; select and document a modest local value during implementation because Arc's numeric timeout is unknown. Deadline publishes the existing terminal empty state, cancels owned work and invalidates further partial/final updates. Cancellation must not wait indefinitely for an ignoring provider before the card can stop loading; test late provider delivery after deadline. Do not create a general timeout library.
- Apply Arc's >49-character snapshot-text eligibility check to extracted meaningful page content, with fixtures for 49/50 and metadata-only/empty pages; first confirm the exact snapshot field in the decompilation so an arbitrary title/URL does not satisfy the threshold. If field identity remains uncertain, retain the current extraction behavior and document the gap instead of presenting a guessed threshold as parity.
- Require complete usable final details after generation; partial stream filtering stays permissive so rows can appear progressively. A blocked final response overrides any earlier partial result. No hard guarantee that an on-device answer equals Arc's cloud output.

## Files expected to change

| Path | Scoped purpose |
| --- | --- |
| `Packages/CraCore/Sources/CraCore/LinkSummary.swift` | Typed key, terminal/cache policy, prompt fitting/schema values, redirect/response decisions and lifecycle value where needed. Split a focused `LinkSummaryRequest.swift` only if this avoids mixing unrelated responsibilities. |
| `Sources/Cra/Services/LinkSummaryService.swift` | Identity-aware caches, owned child work, explicit outcomes, fitted streaming and one overflow retry. |
| `Sources/Cra/Services/LinkSummaryFetch.swift` (new) | Preview-only HTML redirect/cancellation adapter and image operation. No replacement of generic callers. |
| `Sources/CraCEF/include/CraCEF.h`, `Sources/CraCEF/CraCEF.mm` | Preview-specific cancellable bounded single-hop bridge; retain existing generic/plugin contracts. |
| `Sources/Cra/UI/LinkSummaryPreview.swift` | Generation/context guards, finite error/loading state and reused-card state cleanup. Keep measured rendering constants. |
| `Sources/Cra/UI/Windows/MainWindowController.swift` | Forward actual origin identity and inspection href; invalidate on relevant existing lifecycle transitions. |
| `Packages/CraCore/Tests/CraCoreTests/LinkSummaryTests.swift` | Production decision regressions. New focused test files only when warranted by size. |
| `Tests/LinkSummarySupport/*`, `Tests/LinkSummaryPanelTests.swift` | Adapt existing harness service seam and verify state/presentation reuse without introducing window-only test hooks. |
| `Tests/LinkSummaryServiceTests.swift`, `scripts/test-link-summary-service.sh` (new if needed) | Compile actual service/transport Swift files against CEF/model transport boundaries; assert emitted cards/cache results, not fake call bookkeeping alone. |
| `scripts/test.sh`, `docs/development.md` | Register a new harness with sanitizer/coverage/keep flags only if one is added. |
| `docs/release-checklist.md`, `docs/arc-reverse-engineering.md`, `docs/arc-parity.md` | Record verified behavior, retained differences and remaining hardware/real-site limits. Do not overwrite measured evidence. |

## Regression-first verification matrix

| Area | Tests and fault reintroduction evidence |
| --- | --- |
| Isolation | Same URL, profiles A/B and Default; different queries/languages/HTTPS policies. Assert B never receives A's summary, title or image; same full identity still hits bounded cache. Reintroduce URL-only key and observe failure. |
| Stale work | A→B→A, same URL in another window/profile/tab/page, inspection returning changed href, late title/partial/image, stop/reopen and feature disable. Assert only current generation alters the actual produced card. Reintroduce URL-only acceptance and observe failure. |
| Lifetimes | Cancel before CEF profile readiness, during body delivery, between hops, during model and image, and at completion race. Assert one terminal delivery, no stale card/cache entry and released work; repeated cancel is harmless. |
| Fetch | Allowed redirects, relative Location/final-page relative image, missing Location, loop, sixth hop, public→private/non-web/credential URL, HTTPS upgrade at each hop, non-HTML/status failures, empty response, oversized chunk, endless stream and aggregate timeout. Image redirects and streaming cap tested separately. |
| Cache/error | Blocked final response clears partials; failure→next-hover success; no-content→changed-content success; cancelled/partial result never cached; final success cached only for correct identity; cache capacity eviction. |
| Model | Optional summary with valid details; no query vs search focus; blocked/empty final; normal stream and final 2–4 details; enormous every-field input; multilingual/emoji fitting; overflow shrinks once; second overflow terminates; generic/refusal/cancellation never retries. |
| UI | Existing panel/share harnesses still pass. Loading→error ends, loading→partial→final grows with fixed top, reused successful→loading/empty/small clears prior share/result/image, image arriving after final retained only for current request. |
| Neighbor contracts | Existing live-folder and plugin-fetch tests/scenarios retain cookie/profile/redirect/limit behavior; no plugin API/signature or generic fetch flags change. |

Run deterministic pure decisions through CraCore. Extend actual production seams for service tests, using controlled continuations and the injected scheduler, with no sleeps or fake-only assertions. New transport bridge behavior also needs real CEF integration validation: a Swift fake cannot establish CEF cancellation/redirect/body behavior. Use disposable test profiles and a controlled transport fixture; any loopback transport fixture operates below the production public-host gate and introduces no production bypass/allowlist.

Focused commands after approval: `swift test --package-path Packages/CraCore --scratch-path /tmp/cra-5secondpreviews-core --filter LinkSummaryTests`, `scripts/test-link-summary-panel.sh`, `scripts/test-link-summary-share.sh`, new service harness if added, `python3 scripts/lint.py`, `git diff --check`. Record failures before and after fixes. Do not edit locked promises merely to accommodate a failure.

## Granular implementation batches and commit subjects

Each row includes regression-first tests, implementation and focused checks in one reviewable change. Sol review **before each commit**, including redundancy review; fix findings before proceeding.

| Order | Subject | Deliverable |
| --- | --- | --- |
| 1 | `fix(previews): isolate cached content by request context` | Typed identity, all three caches, explicit no-negative-cache policy and isolation/error regressions. |
| 2 | `fix(previews): reject stale hover results` | Origin identity/generation and inspected href checks, current-card state cleanup, cancellation-aware updates. |
| 3 | `fix(previews): bound and cancel page fetches` | Dedicated CEF single-hop operation plus the minimum complete page redirect loop/final-URL handling, cancellation/readiness/deadline/body tests and bridge integration evidence. Generic/plugin routes unchanged. Single-hop activation and redirect handling must land together so ordinary redirected links keep working at this commit. |
| 4 | `fix(previews): validate redirects and own image loads` | Cancellable streamed image cap, image redirect validation and owned post-summary image updates; image ownership regressions. Page redirect correctness already ships with the bridge in step 3. |
| 5 | `fix(previews): match optional summary and search focus` | Guided schema/prompt parity and partial/final validation tests. Recovered text eligibility only if exact source field verified. |
| 6 | `fix(previews): fit local model context and retry overflow` | Combined budgeting, classified single retry and failure/reset regressions. |
| 7 | `docs(previews): record validation and remaining differences` | Only actual test/runtime/Arc comparison evidence, retained adaptations and remaining limits. |

Do not commit deliberately broken intermediate states. If a row becomes too large, split tests plus their minimal production fix by independent behavior, preserving the per-commit review gate. New discoveries requiring changed design return to independent plan review.

## Runtime validation and completion gate

After root coordination, run repository-required `scripts/test.sh`, build release Cra, and use a disposable `CRA_DATA_DIR`. Keep source, tests, build, live CEF behavior and real-model quality as separate evidence.

1. Fake-model UI: compare Arc/Cra on the same display and scale; capture loading/streamed/final/empty/small cards, beige/dark themes, above/below placement, pointer transfer, share text/image and same-URL context switches. Capture motion with timestamps/frame measurements; preserve existing 300 pt geometry. A fake model proves UI/lifecycle only.
2. Controlled CEF: test cancellation before profile ready and during download, oversized/endless body, redirect hop limit and blocked target. Prove the blocked target receives no request. Confirm ordinary authenticated public pages use their own disposable profile cookies, and a second profile cannot reuse their data. Validate images separately.
3. Neighbor regression: exercise an existing live folder and restricted plugin fetch with disposable fixtures; existing generic behavior remains intact.
4. Availability: AI off/preparing/ineligible keeps the feature hidden/unavailable; no model inference/network fetch begins for disabled or incognito requests.
5. Real AI: actual model availability was `available` for the retained four-sample production-model receipt. Those samples establish inference/token/schema execution and limited factual/focus/language behavior, with the quality limits below. They do not establish a broad article/product/reference/blocked-page benchmark, paired Arc answer quality, genuine overflow recovery or end-to-end hover latency. Do not enable system settings without authorization or label fake native outputs as model-quality verification. Further broad inference is not a finalization requirement.
6. Update release checklist only for checks that require a real site, GPU or human view. If AI-on/1x hardware/Arc live validation cannot run, mark those exact checks unverified and report them; passing tests/builds alone does not establish parity.

Completion requires the reviewed implementation and existing regression/build/full-suite evidence, the remaining bounded native observations below, and independent review of the exact final documentation/branch. Any unverified manual, real-site, hardware or model behavior must remain explicitly unverified. Source approval does not complete native acceptance.

## Current validation record, 13 November 2026

Evidence root: `/Users/varunaditya/Desktop/arc-decomp/cra-validation`. Paths in the table are relative to it. These are retained local artifacts, not checked-in portable receipts. Source checkpoint: HEAD `310b84ac4de6807a3d2169ac2066665d60223e75`, tree `097bf07fcc14da7d0f1002ec6eb6750d625b9d95`. Documentation edits change the eventual tree; these identifiers describe the source checkpoint, not a future docs commit.

| Area | Status and exact scope | Receipt |
| --- | --- | --- |
| B1–B6 implementation | PASS independent source reviews: request/cache isolation, stale hover ownership, bounded CEF transport, optional image transport, optional-summary/search-focus schema, fitting and one overflow retry. | `reviews/code-5secondpreviews-01.md` through `-06.md` |
| B7 eligibility | PASS exact source review: synchronous actual setting callback, fresh availability publication guards and repeated observed-off revocation. Actual store/model/bootstrap hook harness: 15 checks; service/controller/SDK harness: 121 checks. Negative parent/callback-removal runs fail the intended assertions. | `reviews/code-5secondpreviews-07.md`, `review-5secondpreviews-07/` |
| Current native build | PASS frozen B7 source. Binary SHA-256 `39bf6524fe7637e19c8f5652690d31c458f956211027d0bbc8f1024f64c42054`. | `logs/5secondpreviews-07-final-native-build.log` |
| Current full suite | PASS coordinated full WMO suite, ending “All tests passed.” No repeated full run needed for this docs-only draft. | `logs/5secondpreviews-07-final-suite-wmo.log` |
| Actual page/profile wire | PASS earlier B3 actual CEF normal/redirect hops, blocked-target zero hits, hop/loop bounds, over-cap disconnect, leave cancellation, aggregate deadline, A/B cookies/cache and restricted-plugin/live-folder smoke. Original source/binary scope retained; no relabeling as current B7 on-screen evidence. | `wire/run-b3-01/handoff.md`, `result.json` |
| Actual image wire | PASS earlier B4 actual URLSession streamed cap, redirect policy, cookie/cache suppression, cancellation and aggregate deadline. Does not establish a current visible banner. | `reviews/code-5secondpreviews-04.md` and its wire receipts |
| Actual model | PASS inference executed with available model through production ask/respond/generate/tokenCount; four typed usable samples. Input totals 594/609/595/602 include schema 364 and instructions 51; B7 preserves this B6 generation/Core path. | `runtime/previews-b7-real-model/readout.json` |
| Current native acceptance | **PENDING.** B8 attempt 03 stopped at readiness: `checks=[]`, `captures=[]`. Main-window 2x/theme/DOM readiness does not prove card pixels or a wire journey. | `runtime/previews-b8-native-2x-03/result.json`, `root-interruption.json`, `capture-diagnostic-summary.json` |
| Final docs/branch review | **PENDING.** This B8 draft must incorporate genuine new native receipts before independent exact-diff review and root-owned finalization. | `reviews/5secondpreviews-final-gap-assessment.md` |

### Model-output disposition and retained limits

| Sample | Observed result | Limit |
| --- | --- | --- |
| Ordinary English | Source-supported access, hours, ticket and tour facts; 6.04 s model-probe completion. | One small synthetic page; no native fetch/hover latency claim. |
| Focused English | Access/elevator facts prioritized; 2.60 s. | Hidden focus contains multiple words; no enforced one-word or universal focus-quality claim. |
| Spanish | Requested-language summary/details; 3.16 s. | Invented an opening-time `userQuestion` without a query. This guidance field is hidden; it is not substituted for quick summary. |
| Japanese | Requested-language values; 5.45 s. | 178-character quick summary largely repeats the source paragraph; access row labeled transport. |

Some generated SF Symbol names use the existing fallback. These observations justify documenting local-model quality limits; they do not require a new model search. Genuine overflow/refusal, older-OS inference, broad site/language quality and paired Arc answers remain unverified. Earlier systems use the compiled/tested conservative fitting fallback; no older-hardware inference claim follows.

Implemented Cra boundaries: regex HTML extraction rather than a rendered DOM snapshot; unresolved exact preview text field for Arc's >49-character cutoff; 1 MiB/20 s page budget and five redirects; 4,000,000-byte/8 s cookie-free optional image budget; 1,536-byte fitted prompt, one compact retry and 18 s model deadline. On 26.4+ actual SDK preflight counts instructions/schema/prompt/transcript and reserves 1,024 output tokens plus 256 safety tokens; earlier systems use conservative fixed overhead. These are local policies, not recovered Arc timings. Controlled public-shaped loopback wire hosts do not establish DNS-rebinding defenses, public-CDN/TLS or decoded-image pixel-allocation limits. Cra attribution, emoji mapping and locally generated answers remain deliberate differences.

### Remaining native operator checklist

All items are **PENDING**. Run only after the user has cleared the unrelated LuLu/Safe Storage and queued helper dialogs. Do not choose security/password/firewall actions, hide or terminate unrelated workflows, or reinterpret an occluded/black child-host capture as a product defect. Preserve failed external fixture attempts as such.

1. **Confirm identity/readiness.** Verify the frozen binary hash above and current source checkpoint; record driver/capture-helper hashes. Use a fresh output directory per attempt. Root owns the existing display wrappers and native app. Confirm the actual preview can be unobstructed before continuing any pointer checkpoint.
2. **Run one complete 2x journey.** In the existing root-owned 2x display setup, run the command below with a new directory. At `checkpoint-ready.json`, inspect `ready-family.png` through CUA, verify the broad fixture page/link is disabled, safely place the pointer in empty right-center page area and create `continue-ready`. Follow only the checkpoint's observed empty-area placement instructions; never select a copy/share action during this script.
3. **Inspect every correlated card.** Review the pinned unique panel captures and their actual dimensions/scale against historical Arc reference: loading/progression/final/terminal, delayed banner before/after, light and dark, 300 pt card, top-anchored growth and above/below placement. The driver seeds Auto light `#C8CAFF`; its beige page alone does not establish a beige space. Add a bounded native beige-space card capture in the disposable profile. A 340 pt outer window includes margins; it alone is not proof of a 300 pt rendered card. Record actual banner arrival or optional-image failure honestly. Verify A/B request cookies/current cache reuse and ordinary leave cancellation from the new log/hit receipts. Do not convert a requested capture label into an observed progressive frame.
4. **Complete interactive checkpoints.** Observe pointer transfer retaining the card, pointer leave dismissing it, share-menu contents and above/below placements. Retain CUA observations/menu screenshots separately from the script continuation tokens. Record representative opening/closing frames/timestamps against the retained .25/.14 s timing contract; no timing claim follows from still images.
5. **Repeat appearance at 1x.** Use a second fresh output directory under the existing root-owned 1x setup, with `--expected-scale 1 --interactive --quick`. Inspect the same card/theme/placement/pointer/menu states and native beige-space card at the independently recorded scale. `--quick` skips the repeated transport-deadline phase only; the first run must retain that phase.
6. **Observe actual eligibility and entry.** In disposable native state, open a current card, turn Settings ▸ Max ▸ 5-Second Previews off and verify that visible card stops, including while the pointer was on it. Restore the disposable setting only for the remaining smoke. Check Shift sampled on entry, same-site small card, and one representative supported-site selector. Record HN/Google/X live-site checks individually as observed or unverified; do not expand into an exhaustive external-site matrix. The driver does not automate this actual-setting or small-card/Shift check.
7. **Check native pasted output only when authorized.** The prepared driver never copies. An authorized bounded manual check must select Copy as Text and Copy as Image, paste into a disposable target and inspect content/current identity, attribution, image and layout. Record both actual pasted outputs. If clipboard use remains unavailable or unauthorized, leave this item **UNVERIFIED**; panel/share harnesses and opening the menu cannot complete it.
8. **Close the record.** Link actual run directories, inspected captures, motion/menu/setting/paste observations and explicit unverified items here and in the release checklist. If a real product defect appears, make only the scoped correction and obtain source re-review. Otherwise obtain independent final docs/exact-branch review. Root alone stages/commits/pushes under the user's authorization; no PR, merge or force-push is part of this checklist.

Prepared command (root executes; this draft did not run it):

```sh
python3 /Users/varunaditya/Desktop/arc-decomp/cra-validation/scripts/previews-b7/native-wire-probe.py \
  --run /Users/varunaditya/Desktop/arc-decomp/cra-validation/runtime/NEW_B8_2X_DIRECTORY \
  --expected-scale 2 --interactive
```

The driver uses actual CEF/profile/image transport and fake generation. It does not change displays, inject global input, copy the clipboard or alter system DNS/proxy settings. Root's physical pointer checkpoints are separate observed native actions. No new product hooks, scenario framework, model benchmark or rerun of the entire old transport matrix is required for finalization.

## Review record

- Plan author: preview implementation agent, 2026-11-12.
- Independent plan reviewer: GPT-6.1 Sol, 2026-11-12.
- Verdict: merge with fixups applied. Clarified hard-stop invalidation despite pointer transfer, owned post-summary image lifetime, static optional search-focus schema adaptation, finite model deadline, and atomic single-hop/page-redirect commit sequencing. Full record: `/Users/varunaditya/Desktop/arc-decomp/cra-validation/reviews/plan-5secondpreviews.md`. Coordinator may now authorize implementation; each source diff still requires review before commit/push.
