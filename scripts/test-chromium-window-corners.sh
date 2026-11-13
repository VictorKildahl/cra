#!/bin/bash
# Docked page/DevTools windows stay square however AppKit asks for their corners: real windows off screen, no CEF (#400).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-window-corners.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Sources/Cra/UI/Windows/ChromiumWindowCorners.swift Tests/ChromiumWindowCornersTests.swift \
  -o "$TEST_DIR/chromium-window-corners-tests"
"$TEST_DIR/chromium-window-corners-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/chromium-window-corners-tests" "$CRA_TEST_KEEP/"
