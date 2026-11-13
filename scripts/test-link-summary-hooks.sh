#!/bin/bash
# Actual SidebarStore/model refresh and production bootstrap binding; no Chromium/model inference.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-link-summary-hooks.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -emit-module -emit-object -parse-as-library -module-name CraCEF \
  Tests/LinkSummarySupport/CraCEF.swift -emit-module-path "$TEST_DIR/CraCEF.swiftmodule" -o "$TEST_DIR/CraCEF.o"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} -I "$TEST_DIR" "$TEST_DIR/CraCEF.o" \
  Packages/CraCore/Sources/CraCore/*.swift Packages/CraCore/Sources/CraCore/Perf/*.swift Sources/Cra/Perf/Perf.swift \
  Sources/Cra/Services/Import/*.swift Sources/Cra/Services/SidebarStore.swift Sources/Cra/Services/SidebarIntegrity.swift \
  Sources/Cra/Services/Persistence.swift Sources/Cra/Services/SettingsSyncService.swift \
  Tests/Support/LegacyLiveFolderResults.swift Sources/Cra/Services/FaviconCache.swift Sources/Cra/Services/SafeStorage.swift \
  Sources/Cra/Services/CraLog.swift Sources/Cra/Services/Scheduler.swift Sources/Cra/Services/TidyTabsService.swift \
  Sources/Cra/Services/LinkSummaryFetch.swift Sources/Cra/Services/LinkSummaryImageFetch.swift Sources/Cra/Services/LinkSummaryService.swift \
  Sources/Cra/UI/LinkSummaryPreview.swift Sources/Cra/UI/LinkSummaryShareImage.swift Sources/Cra/UI/LinkSummaryEligibility.swift \
  Tests/Support/ManualScheduler.swift Tests/LinkSummaryHooksTests.swift -o "$TEST_DIR/link-summary-hooks-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/link-summary-hooks-tests" "$CRA_TEST_KEEP/"
"$TEST_DIR/link-summary-hooks-tests" "$@"
