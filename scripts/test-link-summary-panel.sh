#!/bin/bash
# 5-Second Previews' card window (LinkSummaryPanel, LinkSummaryCardView) off screen, with a stub service.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-link-summary-panel.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
C=Packages/CraCore/Sources/CraCore
{ echo "import Foundation"; sed -n '/^public enum SiteKey {/,/^}/p' $C/LinkRouting.swift; } > "$TEST_DIR/SiteKey.swift"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  $C/LinkSummary.swift $C/LinkSummaryCard.swift $C/LinkSummaryShareBitmap.swift $C/ThemeTones.swift $C/SpaceTheme.swift $C/SpaceThemeVariants.swift \
  "$TEST_DIR/SiteKey.swift" Sources/Cra/Services/Scheduler.swift Sources/Cra/UI/LinkSummaryPreview.swift Sources/Cra/UI/LinkSummaryShareImage.swift \
  Tests/LinkSummarySupport/LinkSummaryServiceStub.swift Tests/LinkSummaryPanelTests.swift -o "$TEST_DIR/link-summary-panel-tests"
"$TEST_DIR/link-summary-panel-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/link-summary-panel-tests" "$CRA_TEST_KEEP/"
