#!/bin/bash
# Production request ownership and FoundationModels adapter; --real-model explicitly runs synthetic on-device samples.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-ask-service.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
C=Packages/CraCore/Sources/CraCore
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  "$C/AskOnPage.swift" "$C/AskOnPagePrompt.swift" "$C/ObserveChanges.swift" \
  Sources/Cra/Services/AskOnPageService.swift Sources/Cra/Services/Scheduler.swift \
  Tests/Support/ManualScheduler.swift Tests/AskOnPageSupport/AppServices.swift \
  Tests/AskOnPageServiceTests.swift -o "$TEST_DIR/ask-service-tests"
"$TEST_DIR/ask-service-tests" "$@"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/ask-service-tests" "$CRA_TEST_KEEP/"
