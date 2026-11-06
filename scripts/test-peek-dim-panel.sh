#!/bin/bash
# The click catcher behind a Peek (PeekDimPanel) and the focus rule for page windows hung on Cra windows (ChromiumChildFocus).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-peek-panel.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/PeekLayout.swift Sources/Cra/UI/Windows/PeekDimPanel.swift \
  Sources/Cra/UI/Windows/ChromiumChildFocus.swift Tests/PeekDimPanelTests.swift \
  -o "$TEST_DIR/peek-panel-tests"
"$TEST_DIR/peek-panel-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/peek-panel-tests" "$CRA_TEST_KEEP/"
