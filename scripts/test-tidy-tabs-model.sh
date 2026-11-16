#!/bin/bash
# The production grouping adapter and SDK schema, without CEF or an app window.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-tidy-tabs-model.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/TidyTabs.swift Sources/Cra/Services/TidyTabsModel.swift \
  Tests/TidyTabsModelTests.swift -o "$TEST_DIR/tidy-tabs-model-tests"
"$TEST_DIR/tidy-tabs-model-tests" "$@"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/tidy-tabs-model-tests" "$CRA_TEST_KEEP/"
