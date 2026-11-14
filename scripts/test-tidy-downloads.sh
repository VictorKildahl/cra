#!/bin/bash
# Production download service and store with suspended inference; no CEF or windows.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-tidy-downloads-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library -emit-module -emit-object -module-name CraCEF \
  Tests/Support/TidyDownloadsCEF.swift -emit-module-path "$TEST_DIR/CraCEF.swiftmodule" -o "$TEST_DIR/CraCEF.o"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} -I "$TEST_DIR" "$TEST_DIR/CraCEF.o" \
  Packages/CraCore/Sources/CraCore/*.swift Packages/CraCore/Sources/CraCore/Perf/*.swift Sources/Cra/Perf/Perf.swift \
  Sources/Cra/Services/Import/*.swift \
  Sources/Cra/Services/SidebarStore.swift Sources/Cra/Services/SidebarIntegrity.swift Sources/Cra/Services/Persistence.swift \
  Sources/Cra/Services/SettingsSyncService.swift \
  Sources/Cra/Services/FaviconCache.swift Sources/Cra/Services/SafeStorage.swift \
  Sources/Cra/Services/CraLog.swift Sources/Cra/Services/Scheduler.swift \
  Sources/Cra/Services/TidyDownloadsService.swift Sources/Cra/Services/TidyDownloadFiles.swift Sources/Cra/Services/TidyTabsService.swift \
  Sources/Cra/Services/DownloadHistory.swift Sources/Cra/Services/DownloadDestinations.swift \
  Tests/Support/TidyDownloadsHistory.swift Tests/Support/ManualScheduler.swift Tests/TidyDownloadsServiceTests.swift -o "$TEST_DIR/tidy-downloads-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/tidy-downloads-tests" "$CRA_TEST_KEEP/"
"$TEST_DIR/tidy-downloads-tests" "$@"
