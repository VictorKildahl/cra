#!/bin/bash
# Current-document extraction in WebKit's real DOM, using the production bounded isolated script.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-ask-content.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
C=Packages/CraCore/Sources/CraCore
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  "$C/AskOnPage.swift" "$C/AskOnPagePrompt.swift" "$C/AskOnPageContent.swift" \
  Tests/AskOnPageContentTests.swift -o "$TEST_DIR/ask-content-tests"
"$TEST_DIR/ask-content-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/ask-content-tests" "$CRA_TEST_KEEP/"
