#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-extension-state.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library Sources/Cra/Services/Import/ExtensionImporter.swift \
  Tests/ExtensionStateTests.swift -o "$TEST_DIR/extension-state-tests"
"$TEST_DIR/extension-state-tests"
