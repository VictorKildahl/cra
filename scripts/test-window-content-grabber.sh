#!/bin/bash
# Page-top window dragging: cursor priority, event delivery, resize edges and child-window coordinates.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-window-grabber-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$TEST_DIR/cache" ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/PageTopDrag.swift \
  Sources/Cra/UI/Windows/WindowContentGrabber.swift Tests/WindowContentGrabberTests.swift \
  -o "$TEST_DIR/window-grabber-tests"
"$TEST_DIR/window-grabber-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/window-grabber-tests" "$CRA_TEST_KEEP/"
