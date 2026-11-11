#!/bin/bash
# Production sidebar lifecycle and shared hit geometry; no CEF/profile/input events.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-sidebar-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} Packages/CraCore/Sources/CraCore/FloatingSidebarGeometry.swift \
  Sources/Cra/UI/Windows/FloatingSidebar.swift Packages/CraCore/Sources/CraCore/SidebarBackdrop.swift \
  Tests/FloatingSidebarTests.swift \
  -o "$TEST_DIR/sidebar-tests"
"$TEST_DIR/sidebar-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/sidebar-tests" "$CRA_TEST_KEEP/"
