#!/bin/bash
# WebKitStores in a fresh process, as at launch, before anything has touched WebKit.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-webkit-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
source scripts/harness-cracore.sh
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  "${CRACORE[@]}" Sources/Cra/Perf/Perf.swift \
  Sources/Cra/Services/WebKit/WebKitStores.swift Sources/Cra/Services/Persistence.swift Sources/Cra/Services/CraLog.swift \
  Tests/WebKitStoresTests.swift -o "$TEST_DIR/webkit-tests"
"$TEST_DIR/webkit-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/webkit-tests" "$CRA_TEST_KEEP/"
