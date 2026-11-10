#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-capture-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -emit-module -emit-library -module-name CraCEF \
  Tests/BrowserManagerSupport/CraCEF.swift -o "$TEST_DIR/libCraCEF.dylib" \
  -emit-module-path "$TEST_DIR/CraCEF.swiftmodule"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} -I "$TEST_DIR" -L "$TEST_DIR" -lCraCEF \
  -Xlinker -rpath -Xlinker "$TEST_DIR" \
  Packages/CraCore/Sources/CraCore/*.swift Packages/CraCore/Sources/CraCore/Perf/*.swift Sources/Cra/Perf/Perf.swift \
  Sources/Cra/App/KeyBindings.swift Sources/Cra/Services/KeyboardLayoutCharacters.swift \
  Sources/Cra/Services/Persistence.swift Sources/Cra/Services/CraLog.swift Sources/Cra/Services/PageScript.swift \
  Sources/Cra/UI/Windows/CaptureOverlay.swift Sources/Cra/UI/Windows/MainWindowController+Capture.swift \
  Sources/Cra/UI/Windows/LittleWindowController+Capture.swift \
  Tests/CaptureOverlaySupport/AppServices.swift Tests/CaptureOverlayTests.swift -o "$TEST_DIR/capture-tests"
CRA_DATA_DIR="$TEST_DIR/data" "$TEST_DIR/capture-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/capture-tests" "$CRA_TEST_KEEP/"
