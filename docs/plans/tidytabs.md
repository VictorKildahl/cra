# Tidy Tabs: Arc behavior with on-device Apple Intelligence

Status: independently reviewed with the bounded request-selection clarifications below; coordinator may authorize implementation. This document alone authorizes no implementation or commit.

Branch: `tidytabs`, based on `fccc893ca3989ebed0485dd9a67622fa7950f0c9`.

## Scope and acceptance

Make Tidy Tabs safer during asynchronous generation, bring its request closer to the recovered Arc builder, and preserve the measured Arc sidebar presentation. Keep Foundation Models on-device, the existing setting and availability checks, native AppKit/Core Animation views, deterministic validation, and undo. Do not modify Tidy Titles, Downloads, Previews, CEF, deployment, persisted data formats, or unrelated sidebar behavior.

The model was disabled during planning and became available on 12 Nov 2026. Deterministic tests and the explicit fake model prove orchestration/UI behavior only. Separately retained production-adapter synthetic runs exercise the real model, with misgrouped or omitted tabs reported alongside successful assignments; they do not establish complete semantic quality or Arc parity.

## Evidence and its limits

| Evidence | Established behavior | Limit |
| --- | --- | --- |
| `/Users/varunaditya/Desktop/arc-decomp/reports/ai-bundle-evidence.md`, Tidy Tabs section; raw `/Users/varunaditya/Desktop/arc-decomp/inventory/ai/0x102a34274.c` | `createUnpinnedTabGroups()` builds an ID/title request and shopping/calendar examples; JSON-encoded example assignments are placed in a code block. | Full system instructions, final validator and mutation are not recovered. Early collection count greater than two is not the final UI eligibility threshold. |
| `/Users/varunaditya/Desktop/arc-decomp/inventory/ai/feature-prompts.json` | Recovered request marker: `Here are my tabs, in the format 'id: title':`; output marker requests assignments as valid JSON in a code block. | Guided Foundation Models output is a deliberate local-backend adaptation; no need to parse free-form Markdown JSON. |
| `docs/arc-reverse-engineering.md`, “Tidy Tabs” (Arc 1.171, 4 Nov 2026) | Six total Today tabs, including grouped tabs, enables the action when there are loose tabs. Measured divider, broom, squiggle, headers, Remove header, Create Folder and undo. Offline Arc hid Tidy after a run that produced no groups. | Arc's server was unavailable. Its real grouping, joining existing groups, and distinction between a successful empty result and a network/model error were not observed. |
| `/Users/varunaditya/Desktop/arc-decomp/CRA_COMPARISON.md` plus current source | CRA uses tab IDs by request position, hosts and existing names; validates assignments well; existing destinations are integer indexes. Failed generation calls `markTidied`. | Comparison is a source audit, not a quality benchmark or proof that Arc's unknown validator is better. |
| Current `TidyTabs.swift`, `TidyTabsService.swift`, `SidebarStore.swift:2061–2190`, `Tests/StoreTests.swift:1542–1620` | Existing production flow and tested undo/store behavior. | Existing tests do not cover a destination removed while the model is running or generation failure. |

Correct the current comments that claim Arc certainly reuses an existing group's name on a second tidy. Preserve that useful existing CRA behavior, but describe it as CRA behavior whose exact Arc equivalent is unverified. Do not replace the documented six-tab UI threshold with the raw builder's preliminary count.

## Current defects to reproduce before fixing

1. **Wrong destination:** snapshot `[A, B, C]`, model chooses B, planner stores join index 1. Remove A's header during inference. Application queries `[B, C]` and sends the new tab into C. Removing B instead can also retarget an old index. The header menu remains available during generation.
2. **Failure consumes the action:** model error becomes `nil`, and `tidy` calls `markTidied`. The same tabs cannot be retried until a new loose tab appears.
3. **Late mutation after opt-out:** the entry guard does not check `settings.tidyTabs` or `store.canTidy`, and the completion checks neither. The task is untracked, so a result can arrive after the setting is disabled. The debug command also invokes the service directly.
4. **Unbounded combined context:** up to 60 × 80 title characters, plus uncapped hosts and existing group names, instructions, schema and output. A fresh session does not make the first request fit. There is no context-specific reduction/retry.
5. **New arrivals consumed by an old run:** `applyTidy` marks all current Today IDs as tidied, including a loose tab created after the request snapshot. A completed old run can therefore suppress the next action for a tab it never considered. Add a regression and fix within this flow.

## Proposed request and identity contract

### Core values and planner

Extend the existing `TidyTabs` core type rather than adding a parallel grouping engine.

- Add an `ExistingGroup` value containing the stable group UUID and name. The service snapshots these together before awaiting.
- Change `Plan.joins` from array indexes to stable group UUIDs. `plan` matches a proposed normalized name against the original snapshot and emits that UUID. Preserve first matching group behavior for duplicate names; do not silently introduce merging of existing groups.
- Keep prompt-local integer tab IDs and the separate immutable `[UUID]` mapping captured for that request. IDs must stay contiguous when input fitting drops trailing tabs. Do not re-index a response against a freshly queried tab list.
- Preserve the validator's current bad-ID rejection, single ownership, name cleaning/capping, merged new names, minimum two tabs for new groups, and ordering. Existing groups may still receive one new member.
- At application, accept a join only if its UUID still names a tab group directly under this request's original space's Today container. A renamed group with the same UUID remains the same destination. A removed/replaced/pinned destination is skipped; a same-named replacement must not inherit the old UUID's assignments.
- Continue revalidating every member as a currently loose tab in that Today container. A pinned, closed, already grouped or moved-away tab is skipped. Recheck new groups still have two live members after filtering.
- A successful run adds only the request's tab IDs to the space's considered set, retaining previously considered surviving IDs (and pruning deleted IDs where useful). Replacing that set with just the latest fitted subset would make older IDs eligible again and cause alternating repeated runs. Tabs arriving during the run remain eligible. Successful empty output records its snapshot; failed/cancelled/stale output does not. Undo retains its current behavior of clearing the considered state.
- Build each request from a deterministic ordering that prioritizes not-yet-considered loose IDs in their current Today order, then uses already considered loose IDs in their current order as optional remaining context. Fit a prefix of that ordering. This prevents the first 60 old tabs, or the first reduced subset, from starving later/new tabs forever. Capture the resulting order and UUID mapping once per attempt; no response is mapped against a fresh order.

No disk format changes are required: group UUIDs already exist. The API change is internal to current core/service/store callers and tests.

### Prompt fidelity and examples

Use the recovered `id: title` request marker and title lines. Remove host suffixes from the model's normal input because those are an extra CRA context field, not established Arc request content. A host can remain the existing fallback display text for a genuinely empty title; this is a disclosed input sanitation choice, not a recovered Arc rule.

Before changing prompt text, inspect the static example data referenced by the raw builder and recover as much of the shopping/calendar titles and assignments as the binary supports. Preserve exact recovered fragments in the evidence notes, including addresses. Port recovered examples to the guided `groups` schema while keeping their assignment semantics. If example bytes or assignment correspondence cannot be recovered, explicitly label any compact analogous example as an adaptation and do not present it as Arc's exact prompt. Do not invent missing full system instructions.

Keep instructions short and local to this feature. Ask for related topics/tasks with concise labels, allow unrelated tabs to remain loose, and retain deterministic two-member validation. Remove the unsupported instruction that the model must make two to six groups; a useful answer may have one group or none. Retain existing-group names in a separately delimited, bounded section to support CRA's existing joining behavior. Document this extension distinctly from the recovered base request. User titles and group names are data; delimiting/encoding must prevent their newlines or punctuation from creating fake IDs or instruction sections.

The fake model must consume the typed captured request, not reverse-parse the changed prompt. It can continue providing deterministic fixture grouping. Its behavior is a UI test mechanism, never evidence of the local model's grouping ability.

### Context fitting and bounded retry

Put deterministic fitting decisions in CraCore; keep framework errors and token counts in the app service.

- Budget instructions, examples, existing group context, tab lines, guided schema overhead and a response reserve together. Set an explicitly conservative request budget for the local 4096-token context; do not equate characters with guaranteed tokens.
- Verify the installed Foundation Models SDK's supported token-count/preflight and context-window error APIs before implementation. Use exact preflight if the shipped SDK exposes it. Otherwise use a documented conservative UTF-8-byte cap for variable fields, plus a fixed measured/reserved allowance for instructions/examples/schema/output. Mark that fallback as an estimate, with context-overflow recovery as the final guard.
- Clamp every variable input, including empty-title host fallbacks and retained existing group names. Fixed examples must fit the fixed allowance. Limit represented group context without changing original UUID/name associations; groups not represented cannot be model join destinations in that request. Do not create ambiguous clipped-name aliases: either retain a safely bounded name that maps unambiguously to its original UUID or omit that group from represented join context. Preserve the existing first-match behavior for genuine duplicate normalized names, without merging distinct originals merely because truncation made them equal.
- Start from a fitted prefix of at most the existing 60 loose tabs, using the unseen-first ordering above. Preserve that captured prefix order and contiguous IDs. On the SDK's specific context-window overflow only, create a fresh session and retry once with a strictly smaller deterministic prefix/context allowance. Record the reduced captured tab IDs with the request. If nothing meaningful fits, return a retryable failure without applying or marking anything.
- Do not retry generic errors or endlessly halve input. Cancellation and disabled/unavailable state stop the attempt. Never run a response from the first attempt against the second attempt's mapping.
- Logs contain counts, outcome categories and elapsed duration only. Never log prompts, titles, URLs, hosts, group names or the raw Foundation Models error description if it may contain request content.

Exact budget constants must be justified by the compiled schema and prompt size during implementation and included in tests/evidence, not asserted as empirically safe for all languages without a live model run.

## Request lifecycle and UI behavior

The service owns one task per `(store identity, space UUID)` with a unique run token. Service entry must recheck setting, availability, non-private space, minimum eligibility and no active run. Avoid keying a singleton's requests only by space UUID across distinct test/store instances.

Use a small production model dependency boundary (typed request in, typed success/failure out) for deterministic contract tests. `LanguageModelSession` stays behind this boundary; fake/test generation returns through the same service code. Production clock scheduling goes through the existing app/store Scheduler. Minimum broom time remains a presentation requirement and must not require real sleeps in tests.

On completion and after any minimum-animation delay, require the run token to remain current; recheck setting, availability and original space/container existence before applying. Use cancellation-aware delays. Clear running state exactly once on every exit, but an old completion must not clear a newer run's state.

Observe the Tidy Tabs setting and space lifetime through the existing production observation mechanism or a narrowly scoped store lifecycle callback. Turning Tidy off, availability becoming unavailable, deleting the space, or service teardown invalidates/cancels affected runs. Switching to another space/window alone does not invalidate a valid request for a surviving space. Closing one of several windows showing that space must not discard legitimate space-scoped work.

| State/outcome | Divider/store behavior |
| --- | --- |
| Hidden | Existing unavailable, disabled, private or ineligible behavior remains. |
| Offered | Existing hover action and tooltip. |
| Running | Existing broom/squiggle and duplicate-request suppression. Header actions and Clear remain available; completion must handle their mutations safely. |
| Successful nonempty plan | Apply validated live members, preserve native move animations and undo. Hide for considered tabs until eligible new tabs arrive. |
| Successful empty plan | No sidebar mutation; consume only the captured IDs, preserving observed no-group behavior. |
| Generation failure or exhausted overflow recovery | End animation; keep eligible action available so the user can retry. No new badge, alert or settings surface. |
| Cancelled/stale request | No mutation or considered-tab update; end only its own running state. |

A failed local-model request staying retryable is an intentional recovery improvement. Offline Arc's inability to group does not establish that its hidden-action behavior was a desirable or distinguishable successful empty response. State this limitation honestly.

Preserve the measured UI geometry and motion: six-tab threshold; 11 pt semibold Tidy label; divider spacing; 12.75 pt wave period, 3 pt amplitude, five cycles/second and 0.4 s ramps; broom shape/pivot and sweep; 41 pt unindented group headers with 13 pt semibold title; hover buttons and Remove header/Create Folder semantics. Change visuals only if new measurements reveal a concrete discrepancy, and then obtain focused review before expanding this plan.

## Files expected to change

| File | Purpose |
| --- | --- |
| `Packages/CraCore/Sources/CraCore/TidyTabs.swift` | Stable group references, fitted typed request and prompt/examples, run/result decisions where pure. Preserve validator/order API behavior except the documented fixes. |
| `Packages/CraCore/Tests/CraCoreTests/TidyTabsTests.swift` | Identity/name matching, request fitting/mapping, prompt/example contract, outcomes and considered-tab decisions. |
| `Sources/Cra/Services/TidyTabsService.swift` | Typed model boundary, fresh bounded overflow retry, task ownership, cancellation/revalidation, private logging, fake request input. Preserve shared availability API used by other features. |
| `Sources/Cra/Services/SidebarStore.swift` | Stable destination application, considered snapshot IDs, narrowly scoped lifecycle notification only if needed. Preserve undo and persistence. |
| `Tests/StoreTests.swift` | Failing reproductions for removed/reordered/replaced groups, changed tab membership, new arrivals, undo and invariants. |
| New `Tests/TidyTabsServiceTests.swift` and `scripts/test-tidy-tabs.sh`, if the existing store harness cannot exercise the app service without UI dependencies | Compile the actual service/store against the typed controllable model and manual scheduler; assert final sidebar, eligibility and running state. New harness follows `CRA_TEST_SWIFTC_FLAGS` / `CRA_TEST_KEEP` conventions. |
| `scripts/test.sh`, `docs/development.md` | Register/document that harness only if introduced. Root coordinates edits to the shared test runner with sibling branches. |
| `Sources/Cra/UI/Sidebar/List/SidebarRowViews.swift` | Only if the service's current dependency on `SidebarTidyMetrics.minimumRun` requires moving that timing constant to a small production file to compile the service harness. No geometry or rendering rewrite. |
| `Tests/Scenarios/tidy-tabs.scenario` | Deterministic end-to-end success, undo, and retry/cancellation where supported by actual production readouts; no new window test hooks. |
| `docs/arc-reverse-engineering.md`, `docs/arc-parity.md`, `docs/release-checklist.md`, this plan | Recovered example evidence, known-vs-unknown claims, deliberate failure recovery behavior and remaining real-model/manual checks. Touch only the Tidy Tabs entries. |

AppDelegate/composition wiring is optional only if needed for lifecycle ownership. Prefer existing observation/service entry points and keep unrelated features untouched. Review the chosen seam before making broad lifecycle changes.

## Tests and bug-first proof

Each bug fix first gets an assertion that fails against the unfixed behavior. Save the command and failing output, then rerun after the fix. For API migrations, first reproduce at the current store/service seam where possible; after migration, mutate the new code to recreate stale-index or failed-result consumption and show the regression still catches it. Do not count a compile failure as the bug-first proof.

| Case | Meaningful assertion |
| --- | --- |
| Remove A while original destination is B | New tab joins B's original UUID, C unchanged; integrity clean. Fails current indexed application. |
| Remove B, then add a same-named group | Tab stays loose; replacement gets no old assignment. |
| Reorder or rename B | Original UUID receives the tab; order/name changes do not retarget it. |
| Destination moved/deleted or source space deleted | No cross-container/space mutation and no stranded running state. |
| Close/pin/group/move input members during inference | Only currently loose original members move; invalidated new groups with fewer than two surviving tabs are not created. |
| Add a tab while model is running | New arrival remains loose and can bring Tidy back after success; old considered IDs do not consume it. |
| More than 60 loose tabs, or a reduced fitted prefix | Repeated successful empty runs eventually consider every surviving loose ID, prioritize new/unseen IDs, and terminate offered state; earlier considered IDs do not become eligible again when recording the later subset. |
| Error, then user retries same tabs | No tree/undo/considered change on error; offered again; second successful request applies normally. Fails current `markTidied` path. |
| Successful empty response | Action hides for that snapshot; no group created; later new tab re-enables. Distinct from failure. |
| Disable setting during pending work and re-enable | Old response cannot apply; re-enable permits a fresh eligible run. Old completion cannot clear the new run. |
| Duplicate click; independent spaces/store identities | One run per target; completion changes only its original target. |
| First call context overflow | Exactly one reduced fresh request, smaller fitted input and correct prompt-ID→UUID correspondence; successful reduced result touches only its own snapshot. |
| Other error / second overflow / cancellation | No retry loop, no mutation, no consumed action. |
| Long ASCII, CJK, emoji, newline/control input, huge group list | Combined deterministic input stays within configured fallback/preflight allowance; every included variable field bounded; valid contiguous IDs and stable group association. |
| Malformed/duplicate IDs, repeated/empty/long names | Existing validator guarantees preserved; normalized duplicate existing names select the original first destination deterministically. |
| Apply then undo with existing joins and new groups | Original loose order restored, pre-existing group retained, new empty groups pruned, persisted format unchanged, integrity clean. |

Model fakes must produce results on demand through the actual model seam. Use manual scheduling/continuations for pause/resume/cancellation; no wall-clock sleeps. Assert actual store/tree/eligibility state, not merely that a fake recorded calls. Existing tests for header actions, round-trip persistence and incognito exclusion remain in the verification set.

## Granular commit sequence and review gates

No source edit begins until a separate agent reviews this plan and root relays the outcome. Incorporate that review here first. Before **every** commit and **every** push, obtain a separate agent's review of that exact diff for correctness, unused/redundant abstractions, scope and regression coverage. Fix findings and request re-review if the reviewed diff changes materially. Commit subjects only, conventional and concise; no bodies. Push only when the root confirms the user's authorization and review gate.

1. `fix(tidy-tabs): preserve existing group identity` — failing store race, stable group UUID plan/application, stale destination and member checks; existing join and undo tests updated.
2. `fix(tidy-tabs): preserve retry eligibility after failure` — failing error/new-arrival cases; typed outcomes, snapshot considered IDs, successful empty result distinction; minimum necessary production model test seam/harness wiring.
3. `fix(tidy-tabs): discard cancelled grouping results` — failing disabled/deleted/late-token cases; tracked tasks, lifecycle invalidation and duplicate request checks through production seams.
4. `fix(tidy-tabs): fit requests to local model context` — failing unbounded-input/overflow cases; bounded typed request, one context-only reduced retry, private outcome logging.
5. `fix(tidy-tabs): align grouping examples with Arc evidence` — recovered/explicitly adapted shopping/calendar examples, ID/title input and guided-output request, exact prompt/fitting tests, fake model consumes typed requests.
6. `test(tidy-tabs): cover grouping and undo journey` — production end-to-end fixture scenario, measured Arc/Cra evidence and focused docs/checklist updates. Combine documentation with its relevant implementation commit where that makes review clearer; do not manufacture a standalone commit without a meaningful measurable change.

If steps 2–3 need one minimal shared lifecycle seam, keep the seam in its first actual consumer's commit and avoid unused APIs. If prompt text changes budget constants, rerun context tests in step 5 and record that coupling. Do not rewrite older commits after approval without another exact-diff review.

## Verification and evidence delivery

During implementation run focused core tests using a branch-specific scratch path outside the source checkout:

`swift test --package-path Packages/CraCore --scratch-path /tmp/cra-tidytabs-core-build --filter 'TidyTabsTests|TabGroupItemTests'`

Run `scripts/test-store.sh`, the service harness if added, lint, and `git diff --check`. Root coordinates full `scripts/test.sh`, CEF builds and app launches; do not run competing full suites/builds while other branches use shared resources. After focused checks pass, root runs the complete required suite on this branch/integration state. Report failing unrelated baseline tests separately; never loosen promises or thresholds to make them pass.

Use a release test copy and throwaway `CRA_DATA_DIR`, never the user's daily profile. With `CRA_TIDY_FAKE_MODEL=1`, capture matching Arc/Cra divider and group-header states at 1x/2x in light/dark on the same display. Record idle/offered/running/success/empty/failure/undo, header removal during delayed inference, Clear during inference and opt-out while running. For motion, compare frame timings and the existing measured metrics, not just a still image. Record Arc's offline/server limitation alongside any fake-model result.

If the real model becomes available, run a separate manual dataset of shopping/calendar and mixed-topic tabs, plus long multilingual titles and many existing groups. Report actual input/output, outcome and elapsed duration using synthetic titles only; compare only properties established by the recovered request and deterministic guarantees. Without that run, explicitly say semantic quality, real model overflow behavior and latency remain unverified. No claim of complete Arc parity.

Final handoff includes reviewed commits, bug-first evidence and green targeted checks, full-suite/build/scenario status supplied by root, paired visual captures, and a compact list of remaining unknowns. No PR, commit or push occurs merely because this plan exists.

## Proposed amendment: newly decoded singleton policy (12 Nov 2026)

Independently reviewed by GPT-6.1 Sol on 12 Nov 2026: approved as the closest supported prompt/example fidelity, with the constraints below. Root must relay approval before validator/application implementation. Full system instructions are now recovered by `/Users/varunaditya/Desktop/arc-decomp/scripts/decode_tidy_tabs_prompt.py`; see `/Users/varunaditya/Desktop/arc-decomp/reports/tidy-tabs-prompt-evidence.md` and the linked inventory text/JSON for exact mapped bytes, key, addresses and hashes. The earlier “full system instructions unknown” boundary is superseded; the final Arc validator/mutation remains unrecovered.

The decoded instruction explicitly says: “Some tabs may be in a group of their own, but you should try to find include each tab in a group if possible.” The static example assigns only `calendar.google.com/0` to Calendar. There is no 2–6-group or minimum-two-members instruction. Asking for that output while silently dropping every singleton conflicts with the closest available request evidence.

Approved minimal correction: accept nonempty new groups in the deterministic planner and at live application, including one surviving eligible tab. Preserve name sanitation, range/dedup checks, stable destinations, current row order, eligible-tab revalidation, undo and empty-header pruning. Group UI/store already support one-member groups after another member closes. Do not claim exact native acceptance: this is the closest behavior supported by the recovered instruction/example while the native final validator remains unknown. Add core/store tests for the exact Calendar example, a live singleton result, an emptied group being skipped, and undo restoring the original order. Update old minimum-two tests to the explicitly approved policy rather than weakening them without explanation. No new UI is needed.

This amendment explicitly supersedes every earlier minimum-two-new-group guarantee and corresponding live-survivor test in this plan; those older paragraphs remain historical planning context. It does not lower the measured six-total-Today-tab action threshold, change the one-loose-tab eligibility requirement, add a compulsory group count, or establish Arc existing-group reuse/native final validation.

Required regression details: the six recovered assignments map to Movies [0, 5], Toaster Shopping [1, 2, 3], Calendar [4] when adapted in that source order to CRA integer IDs. Test the Calendar singleton without weakening invalid-ID, duplicate ownership, empty/invalid-name, normalized-name merging, stable destination or ordering assertions. At live application, one member remaining from an original two-member proposal is also valid; zero surviving eligible members must create no header. Verify singleton undo restores exact loose order and removes its now-empty new header, and closing/removing the only member uses existing empty-header pruning. Keep the six-tab UI threshold tests intact. Account for potentially more returned groups in the existing bounded request/response budget; do not replace the removed assumption with an unsupported 2–6-group hard limit or a new framework.

B3 bounded-request/adapter work and the later exact source diff still need their normal independent code/redundancy review before every commit/push. This amendment approves the narrow policy direction, not unseen implementation. Review record: `/Users/varunaditya/Desktop/arc-decomp/cra-validation/reviews/plan-tidytabs-singletons.md`. No new user permission is required beyond the existing authorized Arc-fidelity work; root relays this independent gate.


## B3 context and live-model evidence

The 2304-byte combined instruction/prompt bound is the conservative macOS 26.0–26.3 fallback, not a universal token count. On macOS 26.4+, allow a bounded 8192-byte initial request and use the SDK's token counts for instructions, actual prompt and guided schema against `SystemLanguageModel.contextSize`, with response/framing reserves. Thus ordinary English batches may use context that fits; prefix reduction is driven by the counted total, not the smaller fallback cap. Every reduction retains unseen-first captured priority and its UUID mapping. No whole-project or provider abstraction is added.

The production adapter has a separate SDK-compiled harness; raw real-model passes are retained under `/Users/varunaditya/Desktop/arc-decomp/cra-validation/logs/tidytabs-b3-real-*.log`. The initial recovered six-tab sample reproduced the three group memberships but used “Shopping” instead of “Toaster Shopping”. An altered input ordering exposed cinema/calendar misclassification; after stronger example/actual-ID separation it correctly paired the movie tabs but omitted one shopping tab. Japanese synthetic input paired recipes/schedules while splitting or omitting a shared travel topic. Preserve these limitations; do not present the structural/budget checks as a quality benchmark pass. Further prompt wording makes ID completeness/shared-keyword intent explicit without weakening the deterministic validator or fabricating page/referral context.

Final B3 budget accounting: macOS 26.0–26.3 starts with at most 2304 combined text bytes, then conservatively estimates one token per text byte plus 512 schema tokens, 256 framing tokens and `max(768, 32 × fitted tab count)` response tokens; captured prefixes reduce until the estimated sum fits actual context size. The response value is a bounded generation cap/reserve, not a tokenizer guarantee or a new group-count rule. macOS 26.4+ starts with at most 8192 bytes and counts actual instructions/prompt/schema tokens before adding those dynamic response/framing reserves. Live production-adapter evidence retained all 60 ordinary English tabs at a total reserved cost of 3421/4096; Unicode stress reduced 41 captured tabs (5578 reserved tokens) to the original 20-ID prefix (3249/4096). No newer-SDK byte-fallback restriction was applied to the English batch.

The final prompt pass reproduced the recovered Movies [0,5], Toaster Shopping [1,2,3], Calendar [4] sample and the reordered English shopping/calendar/movie pairs; it retained all Japanese IDs but split the two Kyoto travel pages into separate singleton groups. Earlier misgrouping/omission logs remain available. This is limited synthetic evidence, not a general quality or complete native-parity claim. Generation-failure action consumption and service lifecycle cancellation remain the explicitly deferred next batch; this context/prompt slice does not claim to fix them.


## B4 completion and B5 final QA boundary (13 Nov 2026)

B4 now implements the deferred failure/retry and service ownership slice, with independent review
and coordinator full native build/full WMO suite passing. Its only Core/UI timing relocation preserves
the existing 0.9 s minimum; B3 instructions, examples, schema and adapter are unchanged. The earlier
B3 paragraph's deferred lifecycle limitation describes that historical batch, not current B4 behavior.

B5 adds the local production `tidy-tabs` offer/group/undo scenario using existing debug/fake surfaces,
and dated parity/release notes. It adds no production readout or new golden image. The five-tab direct
entry is rejected, six tabs offer, the host fake yields three groups including a singleton, and undo
must remove headers/restore exact URL order and offer. The coordinator's strict scene passed; inspected
native 1x/2x evidence includes light offer/running, light/dark result, dark undo/reoffer and short motion
clips. The light undo still is unhovered, and no fresh paired Arc motion measurement is claimed.
An immediate external undo snapshot raced list refresh/fading old rows; actual persisted groups were
already gone, and fresh existing-view polling resolved the probe without a product change. Retain
those attempts and all B3 real-model outcomes/semantic limits above; no new inference was needed.
