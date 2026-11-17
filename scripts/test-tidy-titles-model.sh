#!/bin/bash
# Tidy Tab Titles' model adapter and Arc's answer schema, without CEF or an app window.
# --real also asks the Mac's own model (needs Apple Intelligence) and prints the names it picks.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-tidy-titles-model.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/TidyTitles.swift Sources/Cra/Services/TidyTitlesModel.swift \
  Sources/Cra/UI/Sidebar/List/TidyTitleLayout.swift \
  Tests/TidyTitlesModelTests.swift -o "$TEST_DIR/tidy-titles-model-tests"
"$TEST_DIR/tidy-titles-model-tests" "$@"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/tidy-titles-model-tests" "$CRA_TEST_KEEP/"
