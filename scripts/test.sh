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
suite "Shipped-issue lock" python3 Tests/test_promises.py
suite "Engine element checks" python3 Tests/test_element_checks.py
suite "Chromium filter worker and loader" Tests/test-filter-worker.sh
suite "Filter list scriptlets (#845)" node --test Tests/ScriptletTests.js
suite "Engine security check" python3 Tests/test_engine_security.py
suite "Web features map" python3 -I scripts/web-features.py
suite "Web features check" python3 Tests/test_web_features.py
suite "Notarize dist (#720)" scripts/test-notarize-dist.sh
suite "Load paths (#720)" scripts/test-load-paths.sh
suite "Scenario lines" scripts/test-scenario-line.sh
if [ "${1:-}" != core ]; then
  suite "Browser manager" Tests/test-browser-manager.sh
  suite "Filter group disclosure" scripts/test-filter-group-card.sh
  suite "Ask on Page DOM" scripts/test-ask-on-page-content.sh
  suite "Ask on Page quote scripts" scripts/test-ask-on-page-quotes.sh
  suite "Ask on Page service" scripts/test-ask-on-page-service.sh
  suite "Ask on Page lifecycle" scripts/test-ask-on-page-lifecycle.sh
  suite "iOS popup ownership" scripts/test-mobile-popup.sh
  suite "iPhone SDK check" scripts/test-ios-sdk-check.sh
  suite "Floating sidebar" scripts/test-floating-sidebar.sh
  suite "Space pages mask" scripts/test-pager-mask.sh
  suite "Extension popup candidate" scripts/test-extension-popup-candidate.sh
  suite "Extension popup window" scripts/test-extension-popup-window.sh
  suite "Peek dismiss panel" scripts/test-peek-dim-panel.sh
  suite "Docked window accessibility" scripts/test-docked-window-accessibility.sh
  suite "Window content grabber" scripts/test-window-content-grabber.sh
  suite "5-Second Previews copy" scripts/test-link-summary-share.sh
  suite "5-Second Previews card" scripts/test-link-summary-panel.sh
  suite "5-Second Previews lifecycle" scripts/test-link-summary-service.sh
  suite "5-Second Previews eligibility hooks" scripts/test-link-summary-hooks.sh
  suite "5-Second Previews image transport" scripts/test-link-summary-image.sh
  suite "Capture overlay" scripts/test-capture-overlay.sh
  suite "Dialogs" scripts/test-dialogs.sh
  suite "Sidebar creation menu" scripts/test-sidebar-creation-menu.sh
  suite "Back and Forward history menu" scripts/test-back-forward-menu.sh
  suite "Easel canvas" scripts/test-easel-canvas.sh
  suite "Extension state" scripts/test-extension-state.sh
  suite "Extension store migration" scripts/test-extension-store-migration.sh
  suite "Store and importers" scripts/test-store.sh
  suite "Site icons" scripts/test-site-icons.sh
  suite "Tidy Downloads lifecycle" scripts/test-tidy-downloads.sh
  suite "Tidy Tabs model" scripts/test-tidy-tabs-model.sh
  suite "Tidy Tabs lifecycle" scripts/test-tidy-tabs.sh
  suite "DNS provider menu" scripts/test-dns-provider-menu.sh
  suite "Policies" scripts/test-policies.sh
  suite "Import skipped list" scripts/test-skipped-list.sh
  suite "Content blocker" scripts/test-content-blocker.sh
  suite "WebKit stores" scripts/test-webkit-stores.sh
  suite "Update channels" scripts/test-update-channels.sh
  suite "Feed counts kept on promote" scripts/test-feed-counts.sh
  suite "Command bar glyph" scripts/test-command-bar-glyph.sh
  suite "Command bar address selection" scripts/test-field-editor-selection.sh
  suite "Command bar typing undo" scripts/test-field-typing-undo.sh
  suite "Folder glyph" scripts/test-folder-glyph.sh
  suite "Tidy title layout" scripts/test-tidy-title-layout.sh
  suite "Tidy title requests" scripts/test-tidy-titles.sh
  suite "Tidy title model" scripts/test-tidy-titles-model.sh
  suite "Emoji label" scripts/test-emoji-label.sh
  suite "Theme noise" scripts/test-theme-noise.sh
  suite "Chromium window corners" scripts/test-chromium-window-corners.sh
  suite "Tooltip cover (#770)" scripts/test-tooltip-cover.sh
  suite "Picture in Picture corners" scripts/test-pip-corners.sh
  suite "Picture in Picture overlay" scripts/test-pip-overlay.sh
  suite "Music notes pixels" scripts/test-music-notes.sh
  suite "Live folder plugins" scripts/test-live-folder-plugins.sh
  suite "Key bindings" scripts/test-key-bindings.sh
  suite "Perf recorder" scripts/test-perf.sh
  suite "MCP transport" scripts/test-mcp-transport.sh
  suite "CEF download" python3 Tests/test_cef_download.py
  suite "CEF update check" python3 Tests/test_cef_update_check.py
  suite "Sponsors" python3 Tests/test_sponsors.py
  suite "Lint" scripts/lint.py
fi

if [ ${#failed[@]} -gt 0 ]; then
  printf 'Failed: %s\n' "${failed[@]}"
  exit 1
fi
echo "All tests passed."
