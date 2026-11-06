#!/bin/bash
# Every test that runs without Chromium, a window server session or a profile: what CI runs
# on each pull request. Seconds, and no vendor/cef needed.
#   scripts/test.sh           all of them
#   scripts/test.sh core      only Packages/CraCore (swift test)
# A new harness is one more `suite` line below.
set -uo pipefail
cd "$(dirname "$0")/.."

failed=()
suite() {
  local name="$1"; shift
  echo "==> $name"
  if ! "$@"; then failed+=("$name"); fi
}

suite "CraCore" swift test --package-path Packages/CraCore
suite "Shipped-issue tests" scripts/promises.py
if [ "${1:-}" != core ]; then
  suite "Browser manager" Tests/test-browser-manager.sh
  suite "Floating sidebar" scripts/test-floating-sidebar.sh
  suite "Extension popup candidate" scripts/test-extension-popup-candidate.sh
  suite "Extension popup window" scripts/test-extension-popup-window.sh
  suite "Peek dismiss panel" scripts/test-peek-dim-panel.sh
  suite "Extension state" scripts/test-extension-state.sh
  suite "Extension store migration" scripts/test-extension-store-migration.sh
  suite "Store and importers" scripts/test-store.sh
  suite "Policies" scripts/test-policies.sh
  suite "Command bar glyph" scripts/test-command-bar-glyph.sh
  suite "Perf recorder" scripts/test-perf.sh
  suite "Lint" scripts/lint.py
fi

if [ ${#failed[@]} -gt 0 ]; then
  printf 'Failed: %s\n' "${failed[@]}"
  exit 1
fi
echo "All tests passed."
