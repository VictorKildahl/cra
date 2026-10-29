#!/bin/bash
# Compile the real manager against a deterministic bridge; no Chromium or profile I/O.
set -euo pipefail
cd "$(dirname "$0")/.."
MANAGER_SOURCE="${1:-Sources/Cra/Services/BrowserManager.swift}"
TEST_DIR="$(mktemp -d /tmp/cra-lifecycle-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -emit-module -emit-library -module-name CraCEF \
  Tests/BrowserManagerSupport/CraCEF.swift -o "$TEST_DIR/libCraCEF.dylib" \
  -emit-module-path "$TEST_DIR/CraCEF.swiftmodule"
xcrun swiftc -swift-version 5 -parse-as-library -I "$TEST_DIR" -L "$TEST_DIR" -lCraCEF \
  -Xlinker -rpath -Xlinker "$TEST_DIR" \
  "$MANAGER_SOURCE" Tests/BrowserManagerSupport/AppServices.swift \
  Tests/BrowserManagerLifecycleTests.swift -o "$TEST_DIR/lifecycle-tests"
"$TEST_DIR/lifecycle-tests"
