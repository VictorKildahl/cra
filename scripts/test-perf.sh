#!/bin/bash
# The performance recorder (#91) on a real main run loop: stalls, hang files with a stack, the
# session marker, ownership and the recording switch. Its files go to a temporary folder.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-perf-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/Perf/*.swift Sources/Cra/Perf/Perf.swift Sources/Cra/Perf/MainLoopObserver.swift \
  Sources/Cra/Perf/PerfSamplers.swift Sources/Cra/Perf/PerfFiles.swift Sources/Cra/Perf/PerfRecorder.swift \
  Sources/Cra/Services/CraLog.swift Sources/Cra/Services/Persistence.swift \
  Tests/PerfTests.swift -o "$TEST_DIR/perf-tests"
"$TEST_DIR/perf-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/perf-tests" "$CRA_TEST_KEEP/"
