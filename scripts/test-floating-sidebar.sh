#!/bin/bash
# Production sidebar lifecycle and shared hit geometry; no CEF/profile/input events.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-sidebar-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library Sources/Cra/UI/Windows/FloatingSidebarGeometry.swift \
  Sources/Cra/UI/Windows/FloatingSidebar.swift Tests/FloatingSidebarTests.swift \
  -o "$TEST_DIR/sidebar-tests"
"$TEST_DIR/sidebar-tests"
