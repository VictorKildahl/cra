# Ask on Page validation

R4 records integration evidence for the reviewed R1–R3c implementation. It changes tests and
validation documents, with product source frozen at `653ed22bf6c5f4482fca9ceaf8a9143ace6eea8e`.
This is a partial acceptance record. The reviewed implementation may be published with these
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
| Native CEF routing | Two-match next/previous/wrap, closed→nativeShow and discriminating quote→ordinary nativeNext/nativePrevious passed; ordinary query `cobalt`, fresh generation/count2 and completed conversation retained. | Already-open nativeShow focus and DevTools frontend runtime remain unobserved; no universal exclusivity claim. |
| Privileged extension | Genuine extension ID/realm observed, requesting tabs+find, effective tabs only, `chrome.find` unavailable. | Availability in that context, not an invented foreign native search. Page `window.find`, DOM and resource searches are distinct negative controls. |
| Ordinary native literal | Existing StopFinding(false) on owner change materialized exact `cobalt` selection in the prior pinned tab; selection was empty before stop. | This proves that ordinary case. It does not prove the quote or restored case. |
| #408 tone | Unchanged dark-card scenario passed. | Computed contrast/readouts, not fresh native pixels. |
| Real model | Extended Japanese725-token and large3072-token/fraction0.212897 probes passed their assertions. | Eight-case run had two quality failures; summary length/French extra text and irrelevant source-present quotations remain limitations. Large answer duplicated irrelevant exact quotes. No assertions were weakened. |

Root artifacts live outside the repository under `cra-validation/logs/`, `runtime/` and
`reviews/`. The author ran static checks only for R4 orchestration and did not launch an app,
engine, model, global input or display action. The root author handoff records exact paths and
candidate hashes.

## Basic journey and literal selection are separate

Run from the reviewed checkout and root-built app:

```sh
scripts/scenario.sh ask-on-page
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
empty. That quote selection gate remains open; no product defect is inferred from this
observation alone.

Renderer screenshot diagnostics stopped after one explicit foreground attempt: the bounded
frame fence reported `frameReady=false`, `painted=false`, and requested no screenshot. Earlier
background capture timed out without a response. These are unavailable capture evidence,
not proof of a product rendering defect or of correct native highlighting. No further
speculative capture retry is required.

## Remaining native acceptance

- **Exact native quote highlight/selection:** on HTTP fixtures, observe the complete literal
  symbols/inline NFC/repeated and long-paragraph quote after the actual integrated quote action.
  Verify the active highlighted glyphs and quote Range viewport, with conversation still open.
  Then restore ordinary Find and verify its literal selected occurrence. A count, source-present
  quote, found status or script-only Range result cannot satisfy this gate.
- **Native field-editor input:** observe the actual key `FindBarPanel`, editable field
  `askOnPageInput` and associated NSTextView first responder. Exercise Cmd-F select-all,
  Down/Up, Return/Shift-Return, Cmd-G/Shift-Cmd-G, Escape and caret preservation. The debug key
  seam targets the main/command window and is not proof of Find-panel event delivery.
- **Visible appearance and motion:** compare Arc/Cra on the same display at 1x/2x, light/dark
  including light space on dark Mac, short/overflowing/narrow panel, quote loading/error/hover,
  focus and reduced motion. Width 400/conversation height 450 are maxima; input adds natural
  height. Preserve #408 tone; static colors/animation arguments do not prove runtime fidelity.
- **Engine limits:** preserve the distinction between prevented stale setup, prevented
  new-document/retired renderer leases and invalidation after final IPC authorization. Already
  dispatched IPC cannot be atomically revoked. Real WebKit native Find result/selection and
  remaining command/front-end observability must be described at their observed scope.
- **Model quality:** retain existing failing assertions and report unsupported background,
  transformation/language, answer relevance and citation support limits separately from wiring.

Physical validation must hold the owned disposable app alive and verify its exact PID before
binding CUA. Never bind by app name after the process has exited: that can launch a normal
profile. Root retains responsibility for dialog handling, display restoration and input;
external prompts currently prevent claiming the physical key/pixel gates.
