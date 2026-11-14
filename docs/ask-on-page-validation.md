# Ask on Page validation

R4 records integration evidence for the reviewed R1–R3c implementation at
`653ed22bf6c5f4482fca9ceaf8a9143ace6eea8e`. The 14 November follow-up below adds observed native
cases and published R5 row-fix evidence at `2d7075c63a5587e47fd87968c734399542590340`.
R6’s bounded scroll-fix build/native checks passed at the exact reviewed candidate below.
This is a partial acceptance record. The reviewed implementation is published with these
limitations; the remaining gates stay OPEN and must be observed before declaring complete feature
parity or completing the overall goal. Fake guided output proves wiring; textual source presence does not
prove that a quote supports an answer.

## Recorded evidence

| Boundary | Observed result | Limit |
| --- | --- | --- |
| Root release app | R3b and R3c release builds passed. R3c binary SHA-256 `b07de4e633265c66a00fe29b0241100f4837844b1f7d4b4a42977f93ed246dec`. | Compilation is not native UI/model acceptance. |
| Root full WMO suite | `askonpage-R4-final-suite-wmo.log` ended “All tests passed”; includes 31 real WebKit, 43 selection, 34 service, 339 manager, 114 lifecycle and 531 Store checks, plus separate native input checks. | Run preceded the final basic-scene observation correction; full suite does not run full scenarios. |
| Basic CEF HTTP journey | Final guarded integrated journey passed, 263MB/294ms launch/172ms max stall/1 stall/0.028% recorder cost. | Preserves the pre-existing collapsed-card guard. Exact native literal highlighting is separate. |
| Native generation/lifecycle | Five actual cases passed: A→B→C positive submit, A→B→A final-zero Ask once, old zero→new positive immediate submit, close clear and navigation clear. | Command-attested inputs; no independent field-text readback, forced late native callback, physical key or universal race claim. |
| Actual isolated WebKit | Registered `test-ask-on-page-content.sh` passed31, including inline NFC/literal/repeated quotes, no fuzzy repair, changed DOM, retired/new leases, work bounds and long-paragraph exact Range selection. | Exact production DOM scripts; separate from native Find and visible UI. Long Range viewport was top539/bottom581 in height600. |
| Actual isolated CEF | Exact production-script export matrix passed37 in a named isolated context. Long quote Range top767/bottom810, height860, scroll940. | Script-only selection/viewport, not post-native-Find highlight or physical UI. |
| WebKit page realm | Companion exact-script matrix passed. | CDP facade uses page realm; isolated evidence is the registered31-check harness. |
| Actual CEF/WebKit Find correlation | `find-correlation` passed on branch `822e3ba` / the same `b07de4` app: CEF three-match ordinals 1→2→3→2 through next/nativeNext/nativePrevious, final zero and iframe-only positive; WebKit iframe-only native positive reported count `1` / identifier `-1`, then a new query native zero count `0` / identifier `-1`. Retained `runtime/ask-r4-find-correlation-current/` and `logs/askonpage-R4-find-correlation-current.log`; 277MB/290ms launch/694ms max stall/3 stalls/0.032% recorder cost. | Ask disabled; debug quote-purpose route is not the integrated live-DOM quote operation. WebKit native matchFound is authoritative; main-body script counting omits iframe matches, so max(count,1) is a positive floor, not exact cross-frame count. Ordinal is synthetic and `-1` an identifier sentinel. No physical key, native selection or pixel proof. |
| Native CEF routing | Two-match next/previous/wrap, closed→nativeShow and discriminating quote→ordinary nativeNext/nativePrevious passed; ordinary query `cobalt`, fresh generation/count2 and completed conversation retained. | Already-open nativeShow focus and DevTools frontend runtime remain unobserved; no universal exclusivity claim. |
| Privileged extension | Genuine extension ID/realm observed, requesting tabs+find, effective tabs only, `chrome.find` unavailable. | Availability in that context, not an invented foreign native search. Page `window.find`, DOM and resource searches are distinct negative controls. |
| Ordinary native literal | Existing StopFinding(false) on owner change materialized exact `cobalt` selection in the prior pinned tab; selection was empty before stop. | This proves that ordinary case. It does not prove the quote or restored case. |
| #408 tone | Unchanged dark-card scenario passed. | Computed contrast/readouts, not fresh native pixels. |
| Real model | Extended Japanese725-token and large3072-token/fraction0.212897 probes passed their assertions. | Eight-case run had two quality failures; summary length/French extra text and irrelevant source-present quotations remain limitations. Large answer duplicated irrelevant exact quotes. No assertions were weakened. |

Root artifacts live outside the repository under `cra-validation/logs/`, `runtime/` and
`reviews/`. The author ran static checks only for R4 orchestration and did not launch an app,
engine, model, global input or display action. The root author handoff records exact paths and
candidate hashes.

## Native follow-up, 14 November 2026

R5's reviewed native row fix is published at `2d7075c63a5587e47fd87968c734399542590340`,
reviewed tree `c7e19c8bca4d992463aeb14889c42e77e05729d5`, binary SHA-256
`3a629f6accd65668d9aaa8820600d00593d5257551120c285a272b3c35e4d985`. These physical CEF
observations use fake generation: they establish input/rendering/quote wiring, not model quality,
complete Find exclusivity or paired Arc fidelity. Earlier R4 receipts retain their exact source scope.
Paths below are relative to `/Users/varunaditya/Desktop/arc-decomp/cra-validation`.

| Observed boundary | Result and limit | Receipt |
| --- | --- | --- |
| Physical input and symbol/Unicode literals, retained R4 binary `b07de4` | Cmd-F focused/select-all, insertion-caret edits, positive Return/Shift-Return occurrence navigation, zero-match/follow-up Return, Cmd-G ordinary-Find restoration with conversation retained, and Escape/clean reopen were observed. Actual quote clicks highlighted complete 57-UTF16-unit symbols and inline NFD/NFC Café/CJK/ZWJ source sentences orange. This is representative CEF evidence; it does not establish every key or WebKit native behavior. | `runtime/ask-r4-physical-cef-1x-20261114-01/root-observations.jsonl` |
| R5 native row at 1x | Actual normal 400×49 and narrow 232×49 pt/pixel captures show readable single-line Ask/count/arrows/close without overlap. The nominal `narrow240` filename is not an observed width; a still narrower case's count truncation was observed without exact panel-width measurement. | `runtime/ask-r5-row-candidate-1x-20261114/row-fix-native-summary.json`, `root-observations.jsonl` |
| R5 repeated and long exact quote | Actual integrated quote action selected the second complete repeated sentence, retaining conversation. The late 52-UTF16-unit literal was visibly orange across four wrapped lines; independent read-only Range geometry was top 668/bottom 811 in an 860 pt viewport, scrollY 1204. DOM Selection was empty during native Find; geometry supports the separate physical glyph observation. | `runtime/ask-r5-row-candidate-1x-20261114/root-observations.jsonl`, `repeated-native-second-family.png`, `long-native-late-quote-family.png` |
| R5 overflow, themes and genuine missing quote | Light/dark 400×499 pt card, scrollbar/fades/input and retained four-message conversation were observed. After actual DOM target mutation, Find on Page showed the red quote-not-found warning. The settled conversation initially remained at scroll 0 with the newest answer hidden; AX ScrollDown exposed it. This is the R6 trigger, not a successful automatic reveal. | `runtime/ask-r5-row-candidate-1x-20261114/root-observations.jsonl` |
| Exact R5 2x light-card capture | Exact PID 88657/window 1543 SCK capture was 400×499 pt → 800×998 pixels, scale 2, with current mode 83 stable immediately before/after; root inspected the light card/error/scrollbar/fades/input. Root recorded wrapper restoration to mode 82 with exit 0. Earlier files labeled `2x` whose actual metadata was 1x remain 1x evidence. This is a still-image state, not motion or dark-at-2x proof. | `runtime/ask-r5-native-2x-bounded-20261114/result.json`, `window.png`; restoration/inspection in the R5 `root-observations.jsonl` |

R6 is independently reviewed and committed as `5c91655b3341e609a1172476c39230d15dc8c287`,
exact tree `f8700b21fafecbc16db6b44772435c207a1569b4`, canonical reviewed diff SHA-256
`269191afcdbbbcd90ef03b68d9f28855bd049a4d907a3208e82fce1c2746d95c`. Root’s build passed
(`logs/askonpage-R6-scroll-native-build-20261114.log`); binary SHA-256
`0d4dea1cb4bc0bddd677fc0669c0bc9d801f95161b875d4312c28d42261b3275`. Root reports lint clean
with 30 grandfathered findings. Final review: `reviews/code-askonpage-R6-conversation-scroll.md`.

In `runtime/ask-r6-scroll-candidate-cef-20261114/root-observations.jsonl`, four physical turns,
including fast follow-ups, revealed the newest question/answer. After AX ScrollUp to older content, a physical fifth
follow-up moved the scrollbar 0→1 and exposed its question and complete answer without manual downward
scrolling. At older position `0.1038696537678208`, an actual changed-DOM quote error and light-appearance
change retained that exact scroll position and all five messages. The native newest/older captures
record the 400×499 pt 1x card; this is a bounded post-layout reveal/preserved-position pass, not a
physical mid-stream scrolling claim. The R6 2x receipt at
`runtime/ask-r6-native-2x-bounded-20261114/result.json` binds PID 23762/window 1965 to 400×499 pt →
800×998 pixels, stable mode 83 before/after. Root inspected the light older-position/fades image and
recorded restoration to mode 82, exit 0, in the R6 observations.

The owned R6 WebKit run `runtime/ask-r6-native-webkit-20261114/` binds source `5c91655`, the
same `0d4dea` binary and PID 27733 to the actual localhost WebKit engine. Physical Cmd-F/Return,
Shift-Cmd-G previous/wrap and Down/Up navigated ordinary `cobalt` occurrences. A physical zero-match
Budget question/Return generated one fake-provider answer; the actual quote click visibly selected
the entire 57-UTF16-unit symbol literal gray with conversation retained. Its correlated read-only
probe confirmed `exactSelection=true`, 57 units, top 224/bottom 242 in an 860 pt viewport. After
Cmd-F/type `cobalt`/Cmd-G restored ordinary Find with message/input retained, Down/Up selected the
second/first occurrences; the final probe confirmed exact 6-unit selection at top 320/bottom 338.
Native AX focus identified `askOnPageInput`; no internal NSTextView-class introspection is claimed.
See `root-observations.jsonl`, `native-webkit-literal-family.png`,
`native-webkit-restored-first-family.png` and correlated probes in `stdout.log`. Owned cleanup exited 0.

Reduced motion, physical manual scrolling during a still-streaming answer, paired Arc motion/
appearance and remaining hover states stay unverified; the original real-model quality failures
remain recorded. Unobserved native WebKit Unicode/repeated/long/iframe selection cases are
**coverage limits**, not a new mandatory matrix. The user's deferred physical-hover validation applies to Preview only;
these receipts do not establish full Ask parity or overall-goal completion.

## Basic journey and literal selection are separate

Run from the reviewed checkout and root-built app:

```sh
scripts/scenario.sh ask-on-page
scripts/scenario.sh find-correlation  # Ask disabled; native result correlation, not selection/pixels
CRA_TEST_SWIFTC_FLAGS=-whole-module-optimization scripts/test-ask-on-page-content.sh
```

The HTTP basic journey covers final owned ordinary zero before Return, one guided service,
verified quote completion, correlated native quote purpose, retained conversation, restored
ordinary input/query, local fitting disclosure, navigation clear and close/reopen. The initial
R4 scene failed three immediate `window.getSelection()` assertions. Its other feature and
budget assertions passed. Those artifacts are preserved; the corrected scene does not claim
native literal selection.

Blink native Find stores its active match separately and clears DOM Selection while finding.
An empty `window.getSelection()` during active CEF Find is therefore not a failed literal
match witness. Source tracing is recorded in the external native-selection report; actual
ordinary Stop(false) conversion was observed. The quote Stop(false) experiment retained the
conversation before owner change and cleared it after, but its old-tab DOM selection stayed
empty. That historical DOM-selection experiment did not establish native quote glyphs; the
representative 14 November CEF physical observations above supply separate evidence. No product
defect is inferred from the empty DOM Selection alone.

Earlier renderer screenshot diagnostics stopped after one explicit foreground attempt: the bounded
frame fence reported `frameReady=false`, `painted=false`, and requested no screenshot. Earlier
background capture timed out without a response. These are unavailable capture evidence,
not proof of a product rendering defect or of correct native highlighting. The later native
SCK/CUA receipts above have their own observed scale/identity and do not relabel those failures.

## Upstream synchronization, 14 November 2026

The merge target is `56be95df6bbe51d21eb97c85a0e28d872b9c9188`. The guided adapter retains
its native fields, exact transmitted-source validation, quoted bounded history and complete-object
requirement. Upstream's raw-response model fixes are not evidence that the same failure occurs or
is fixed in this adapter. Existing model-quality failures and native acceptance limits still apply.

| Upstream regression | Guided branch resolution and evidence boundary |
|---|---|
| #417 dialogue framing and repeated prior answer | `AskOnPagePromptTests.theModelIsNotToldToWriteADialogue` checks no generated-dialogue framing and an isolated current question. `AskOnPageServiceTests.aFollowUpKeepsItsOwnCurrentQuestionAndAnswer` checks two distinct streamed/completed answers and their exact citations. These use the production fitting/service seams; they do not prove model quality or claim native transcript turns. |
| Hypothetical-example contamination and follow-up quote reminder | Guided instructions and field guides already require excerpts from the current source and the current question; completion rejects absent-source excerpts. Historical guided examples remain. Neither removal of examples nor a raw `<excerpt>` reminder is claimed implemented or measured here. |
| Raw long-answer history/context and overflow | Existing prompt tests evict whole old turns before fitting a page prefix. Service tests require an incomplete guided object to remain incomplete and permit only one bounded overflow refit. Keeping a partial raw string would violate that contract. |
| Raw quote validation before Find | `quotesRequireTheExactTransmittedSource`, `zeroOrInvalidCitationsDoNotInvalidateAnOtherwiseCompleteAnswer` and service tests already validate completed fields before enabling evidence. Full literal validation remains stricter than upstream's shortened/fuzzy quote lookup. |
| Raw echo rejection/retry and 10 Hz, line-by-line streaming | No typed-path reproduction was established. No speculative prefix rejection/retry or pacing path was added; legitimate literal transformations and existing interrupted-stream semantics remain intact. Typed echo quality and long-stream performance remain unverified. |
| #418 floating-toolbar Find/Ask placement | Upstream toolbar following/hover policy and ordinary Find placement are retained. Guided card fitting additionally subtracts the toolbar cover before computing available height. `aFloatingToolbarLeavesTheAskCardInsideAShortFocusedPage` covers narrow/short/fully-covered pages; existing upstream placement/toolbar tests are unchanged. Native movement/hover remains a runtime check. |

Two newly upstream, raw-provider-only scenarios are deliberately excluded from this guided branch:

- `Tests/Scenarios/ask-on-page-echo.scenario` requires a fake raw page-block echo, the log
  `Ask on Page: the answer repeated the page; asking again`, and a retried completed answer.
  The guided fixture does not generate that raw echo. There is no equivalent guided echo-retry pass.
- `Tests/Scenarios/ask-on-page-long-answer.scenario` requires a fake 28-point streamed summary
  with zero quotes, a quoted follow-up, and a fake made-up quote yielding the raw-parser warning
  log and `search=[notFound]`, under `stalls50=10 stalls16=20`. The guided fixture selects a literal
  fitted-source sentence instead. Existing service tests cover distinct follow-ups and rejected
  citations, and the ordinary guided scenario covers the production card journey. They do not
  substitute for the excluded long-stream performance or model-summary assertions.

The two new upstream #417 lock entries move to the applicable guided prompt/service tests above.
Every promise already present at pre-merge branch `a99ac85` retains its exact test hash. The older
raw #393 parser/budget/quote-fallback locks had already been replaced by the guided implementation
before this merge; no existing guided expectation was loosened. Independent review must check
these explicit migrations and exclusions before publication.

## Remaining native acceptance

- **Exact native quote highlight/selection:** representative CEF symbols/inline NFC/repeated/long
  glyphs and ordinary-Find restoration were physically observed above, with WebKit symbol and
  ordinary literal selection separately observed on R6. Preserve exact fixture/source/engine scope;
  unobserved WebKit Unicode/repeated/long/iframe cases are **coverage limits**, not a new mandatory matrix. A count, source-present
  quote, found status or script-only Range result cannot substitute for glyph evidence.
- **Native field-editor input:** retain recorded CEF Cmd-F/caret/Return/Shift-Return/Cmd-G/Escape
  cases and R6 WebKit Cmd-F/Return/Shift-Cmd-G/Down/Up at their respective source/engine scopes.
  WebKit AX focus identified `askOnPageInput`; Tab/Shift-Tab and an internal NSTextView
  first-responder-class readback remain unobserved. The debug key seam targets the main/command
  window and is not proof of physical Find-panel event delivery.
- **Visible appearance and motion:** retain observed 1x light/dark/overflow/narrow and exact
  2x light-card stills above. Paired Arc comparison, light-space-on-dark-Mac combinations,
  remaining hover/loading states, motion and reduced motion stay open. Width 400/conversation
  height 450 are maxima; input adds natural height. Preserve #408 tone. R6's tested fast-overflow
  reveal and same-question layout/error position preservation passed at the candidate above;
  physical manual scrolling during still-streaming output remains unobserved.
- **Engine limits:** preserve the distinction between prevented stale setup, prevented
  new-document/retired renderer leases and invalidation after final IPC authorization. Already
  dispatched IPC cannot be atomically revoked. WebKit iframe-only native positive floor and
  subsequent native zero were observed in find-correlation. This does not establish an exact
  cross-frame count or iframe native selection. The later WebKit native symbol/ordinary-selection
  cases above are separate evidence. Remaining command/front-end observability stays at its
  recorded scope.
- **Model quality:** retain existing failing assertions and report unsupported background,
  transformation/language, answer relevance and citation support limits separately from wiring.

Physical validation must hold the owned disposable app alive and verify its exact PID before
binding CUA. Never bind by app name after the process has exited: that can launch a normal
profile. Root retains responsibility for dialog handling, display restoration and input;
earlier unrelated security prompts are not a blanket current blocker. Claim only the observed
physical cases above; no other manual gate is implied complete.
