#!/bin/bash
# Native pinned-title font and current drawable-width contract, without CEF or visible windows.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-tidy-title-layout.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/TidyTitles.swift Sources/Cra/UI/Sidebar/List/TidyTitleLayout.swift \
  Tests/TidyTitleLayoutTests.swift -o "$TEST_DIR/tidy-title-layout-tests"
"$TEST_DIR/tidy-title-layout-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/tidy-title-layout-tests" "$CRA_TEST_KEEP/"
