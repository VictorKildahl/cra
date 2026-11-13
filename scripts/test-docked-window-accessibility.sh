#!/bin/bash
# Docked child windows answer accessibility as parts of their parent window (#391); real
# offscreen windows, no CEF, no accessibility permission, no input events.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-docked-ax-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} Sources/Cra/UI/Windows/DockedWindowAccessibility.swift \
  Tests/DockedWindowAccessibilityTests.swift \
  -o "$TEST_DIR/docked-ax-tests"
"$TEST_DIR/docked-ax-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/docked-ax-tests" "$CRA_TEST_KEEP/"
