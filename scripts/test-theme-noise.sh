#!/bin/bash
# The theme's grain over the main window: tiled by Core Animation, no window-sized backing store, same pixels.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-theme-noise.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Sources/Cra/UI/ThemeNoise.swift Tests/ThemeNoiseTests.swift \
  -o "$TEST_DIR/theme-noise-tests"
"$TEST_DIR/theme-noise-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/theme-noise-tests" "$CRA_TEST_KEEP/"
