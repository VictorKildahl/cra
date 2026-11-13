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
  suite "Ask on Page DOM" scripts/test-ask-on-page-content.sh
  suite "Ask on Page service" scripts/test-ask-on-page-service.sh
  suite "Ask on Page lifecycle" scripts/test-ask-on-page-lifecycle.sh
  suite "Floating sidebar" scripts/test-floating-sidebar.sh
  suite "Extension popup candidate" scripts/test-extension-popup-candidate.sh
  suite "Extension popup window" scripts/test-extension-popup-window.sh
  suite "Peek dismiss panel" scripts/test-peek-dim-panel.sh
  suite "Docked window accessibility" scripts/test-docked-window-accessibility.sh
  suite "Window content grabber" scripts/test-window-content-grabber.sh
  suite "5-Second Previews copy" scripts/test-link-summary-share.sh
  suite "5-Second Previews card" scripts/test-link-summary-panel.sh
  suite "Capture overlay" scripts/test-capture-overlay.sh
  suite "Dialogs" scripts/test-dialogs.sh
  suite "Sidebar creation menu" scripts/test-sidebar-creation-menu.sh
  suite "Easel canvas" scripts/test-easel-canvas.sh
  suite "Extension state" scripts/test-extension-state.sh
  suite "Extension store migration" scripts/test-extension-store-migration.sh
  suite "Store and importers" scripts/test-store.sh
  suite "Policies" scripts/test-policies.sh
  suite "Command bar glyph" scripts/test-command-bar-glyph.sh
  suite "Folder glyph" scripts/test-folder-glyph.sh
  suite "Emoji label" scripts/test-emoji-label.sh
  suite "Chromium window corners" scripts/test-chromium-window-corners.sh
  suite "Music notes pixels" scripts/test-music-notes.sh
  suite "Live folder plugins" scripts/test-live-folder-plugins.sh
  suite "Key bindings" scripts/test-key-bindings.sh
  suite "Perf recorder" scripts/test-perf.sh
  suite "MCP transport" scripts/test-mcp-transport.sh
  suite "CEF download" python3 Tests/test_cef_download.py
  suite "CEF update check" python3 Tests/test_cef_update_check.py
  suite "Lint" scripts/lint.py
fi

if [ ${#failed[@]} -gt 0 ]; then
  printf 'Failed: %s\n' "${failed[@]}"
  exit 1
fi
echo "All tests passed."
