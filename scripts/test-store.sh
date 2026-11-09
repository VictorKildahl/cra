#!/bin/bash
# The production store, AppComposition and importers on a manual clock; no CEF or AppKit windows.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-store-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/*.swift Packages/CraCore/Sources/CraCore/Perf/*.swift Sources/Cra/Perf/Perf.swift \
  Sources/Cra/Services/Import/*.swift \
  Sources/Cra/Services/SidebarStore.swift Sources/Cra/Services/SidebarIntegrity.swift Sources/Cra/Services/Persistence.swift \
  Sources/Cra/Services/SettingsSyncService.swift \
  Tests/Support/LegacyLiveFolderResults.swift Sources/Cra/Services/FaviconCache.swift Sources/Cra/Services/SafeStorage.swift \
  Sources/Cra/Services/CraLog.swift Sources/Cra/Services/Scheduler.swift \
  Sources/Cra/App/AppComposition.swift Sources/Cra/App/FeatureFlags.swift \
  Tests/Support/ManualScheduler.swift Tests/StoreTests.swift -o "$TEST_DIR/store-tests"
"$TEST_DIR/store-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/store-tests" "$CRA_TEST_KEEP/"
