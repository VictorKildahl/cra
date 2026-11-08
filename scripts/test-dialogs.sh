#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp/}cra-dialog-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/*.swift Packages/CraCore/Sources/CraCore/Perf/*.swift \
  Sources/Cra/UI/Colors.swift Sources/Cra/UI/BrandMark.swift \
  Sources/Cra/UI/Windows/DialogComponents.swift Sources/Cra/UI/Windows/AppDialog.swift \
  Tests/DialogTests.swift -o "$TEST_DIR/dialog-tests"
"$TEST_DIR/dialog-tests" "$@"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/dialog-tests" "$CRA_TEST_KEEP/"
