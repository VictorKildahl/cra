#!/bin/bash
# The production pinned-title service and store, with a manual clock and deferred model answers.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-tidy-titles.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/*.swift Packages/CraCore/Sources/CraCore/Perf/*.swift Sources/Cra/Perf/Perf.swift \
  Sources/Cra/Services/Import/*.swift \
  Sources/Cra/Services/SidebarStore.swift Sources/Cra/Services/SidebarIntegrity.swift Sources/Cra/Services/Persistence.swift \
  Tests/Support/LegacyLiveFolderResults.swift Sources/Cra/Services/FaviconCache.swift Sources/Cra/Services/SafeStorage.swift \
  Sources/Cra/Services/CraLog.swift Sources/Cra/Services/Scheduler.swift \
  Sources/Cra/Services/TidyTitlesService.swift Sources/Cra/UI/Sidebar/List/TidyTitleLayout.swift \
  Tests/Support/TidyTitlesServiceSupport.swift Tests/Support/ManualScheduler.swift \
  Tests/TidyTitlesServiceTests.swift -o "$TEST_DIR/tidy-titles-tests"
"$TEST_DIR/tidy-titles-tests" "$@"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/tidy-titles-tests" "$CRA_TEST_KEEP/"
