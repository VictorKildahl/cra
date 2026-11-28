#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-filter-group.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/SidebarSide.swift \
  Packages/CraCore/Sources/CraCore/FloatingSidebarGeometry.swift Packages/CraCore/Sources/CraCore/PageMargin.swift Sources/Cra/UI/Settings/SettingsKit.swift Sources/Cra/UI/Settings/FilterListGroupCard.swift \
  Tests/FilterListGroupCardTests.swift -o "$TEST_DIR/filter-group-tests"
"$TEST_DIR/filter-group-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/filter-group-tests" "$CRA_TEST_KEEP/"
