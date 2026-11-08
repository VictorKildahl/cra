#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-popup-window.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -emit-module -emit-library -module-name CraCEF \
  Tests/BrowserManagerSupport/CraCEF.swift -o "$TEST_DIR/libCraCEF.dylib" \
  -emit-module-path "$TEST_DIR/CraCEF.swiftmodule"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} -I "$TEST_DIR" -L "$TEST_DIR" -lCraCEF \
  -Xlinker -rpath -Xlinker "$TEST_DIR" \
  Sources/Cra/UI/Windows/ExtensionPopupWindow.swift Tests/ExtensionPopupWindowTests.swift \
  -o "$TEST_DIR/popup-window-tests"
"$TEST_DIR/popup-window-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/popup-window-tests" "$CRA_TEST_KEEP/"
