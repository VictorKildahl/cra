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
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} -I "$TEST_DIR" -L "$TEST_DIR" -lCraCEF \
  -Xlinker -rpath -Xlinker "$TEST_DIR" \
  "$MANAGER_SOURCE" Sources/Cra/Services/NowPlaying.swift Sources/Cra/Services/PageScript.swift Sources/Cra/Services/Scheduler.swift Sources/Cra/Services/DevToolsToggle.swift Sources/Cra/Services/CraLog.swift Sources/Cra/Services/PageProbe.swift Sources/Cra/Services/Persistence.swift Tests/Support/ManualScheduler.swift Tests/BrowserManagerSupport/AppServices.swift \
  Tests/BrowserManagerLifecycleTests.swift -o "$TEST_DIR/lifecycle-tests"
"$TEST_DIR/lifecycle-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/lifecycle-tests" "$CRA_TEST_KEEP/"
