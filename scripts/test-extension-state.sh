#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-extension-state.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} Sources/Cra/Services/Import/ExtensionImporter.swift \
  Packages/CraCore/Sources/CraCore/ExtensionIcons.swift \
  Tests/ExtensionStateTests.swift -o "$TEST_DIR/extension-state-tests"
"$TEST_DIR/extension-state-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/extension-state-tests" "$CRA_TEST_KEEP/"
