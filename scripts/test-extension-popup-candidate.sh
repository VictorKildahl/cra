#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-popup-candidate.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library Sources/Cra/UI/Windows/ExtensionPopupCandidate.swift \
  Tests/ExtensionPopupCandidateTests.swift -o "$TEST_DIR/candidate-tests"
"$TEST_DIR/candidate-tests"
