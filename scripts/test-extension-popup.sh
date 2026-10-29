#!/bin/bash
# Fast geometry regression checks; no CEF download or browser profile needed.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-popup-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library Sources/Cra/UI/Windows/ExtensionPopupGeometry.swift \
  Sources/Cra/Services/ExtensionPopupRequest.swift \
  Tests/ExtensionPopupGeometryTests.swift -o "$TEST_DIR/popup-tests"
"$TEST_DIR/popup-tests"
"$TEST_DIR/popup-tests" --cleanup-expression > "$TEST_DIR/cleanup.js"
node Tests/ExtensionPopupCleanupTests.js "$TEST_DIR/cleanup.js"
xcrun swiftc -parse-as-library Sources/Cra/Services/ExtensionProtocolReply.swift \
  Tests/ExtensionProtocolReplyTests.swift -o "$TEST_DIR/protocol-tests"
"$TEST_DIR/protocol-tests"
