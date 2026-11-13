#!/bin/bash
# Production preview lifecycle against controlled fetch/model boundaries, no CEF/model inference.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-link-summary-service.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
C=Packages/CraCore/Sources/CraCore
{ echo "import Foundation"; sed -n '/^public enum SiteKey {/,/^}/p' "$C/LinkRouting.swift"; } > "$TEST_DIR/SiteKey.swift"
xcrun swiftc -swift-version 5 -emit-module -emit-object -parse-as-library -module-name CraCEF \
  Tests/LinkSummarySupport/CraCEF.swift -emit-module-path "$TEST_DIR/CraCEF.swiftmodule" -o "$TEST_DIR/CraCEF.o"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} -I "$TEST_DIR" \
  "$C/LinkSummary.swift" "$C/LinkSummaryCard.swift" "$C/ThemeTones.swift" "$C/SpaceTheme.swift" "$C/SpaceThemeVariants.swift" \
  "$TEST_DIR/SiteKey.swift" "$TEST_DIR/CraCEF.o" Sources/Cra/Services/Scheduler.swift Tests/Support/ManualScheduler.swift \
  Sources/Cra/Services/LinkSummaryFetch.swift Sources/Cra/Services/LinkSummaryImageFetch.swift Sources/Cra/Services/LinkSummaryService.swift Sources/Cra/UI/LinkSummaryPreview.swift Sources/Cra/UI/LinkSummaryShareImage.swift \
  Tests/LinkSummarySupport/ModelAvailability.swift Tests/LinkSummaryFetchTests.swift Tests/LinkSummaryServiceTests.swift -o "$TEST_DIR/link-summary-service-tests"
"$TEST_DIR/link-summary-service-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/link-summary-service-tests" "$CRA_TEST_KEEP/"
