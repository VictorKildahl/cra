#!/bin/bash
# The engine's ad and tracker matching (Sources/CraCEF/CraContentBlocker.h, built into Chrome's framework
# by engine/chromium/cra) on Cra's own list, called from Swift through a C shim.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-content-blocker.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun clang++ -std=c++17 -O1 -I Sources/CraCEF -I Tests/ContentBlockerSupport \
  -c Tests/ContentBlockerSupport/ContentBlockerShim.cpp -o "$TEST_DIR/shim.o"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  -import-objc-header Tests/ContentBlockerSupport/ContentBlockerShim.h \
  Tests/ContentBlockerTests.swift "$TEST_DIR/shim.o" -lc++ -o "$TEST_DIR/content-blocker-tests"
"$TEST_DIR/content-blocker-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/content-blocker-tests" "$CRA_TEST_KEEP/"
