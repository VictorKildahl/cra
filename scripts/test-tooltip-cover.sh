#!/bin/bash
# A tab's tip only for a pointer on the tab, not on a list hung over it (#770).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-tooltip-cover.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Sources/Cra/UI/TooltipCover.swift Tests/TooltipCoverTests.swift \
  -o "$TEST_DIR/tooltip-cover-tests"
"$TEST_DIR/tooltip-cover-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/tooltip-cover-tests" "$CRA_TEST_KEEP/"
