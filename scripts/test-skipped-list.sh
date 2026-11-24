#!/bin/bash
# The import window's skipped list (SkippedList) off screen: a long list opens without building every row.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-skipped-list.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/ImportReport.swift Packages/CraCore/Sources/CraCore/ImportedAddress.swift \
  Packages/CraCore/Sources/CraCore/AppLinks.swift \
  Sources/Cra/UI/Onboarding/ImportColors.swift Sources/Cra/UI/Onboarding/SkippedList.swift \
  Tests/SkippedListTests.swift -o "$TEST_DIR/skipped-list-tests"
"$TEST_DIR/skipped-list-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/skipped-list-tests" "$CRA_TEST_KEEP/"
