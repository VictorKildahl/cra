#!/bin/bash
# The mask over the sidebar's space pages on real Core Animation layers: its size follows the column at once, its
# downloads fade eases (#679). No CEF or window.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-pager-mask.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Sources/Cra/UI/Sidebar/List/PagerMask.swift Tests/PagerMaskTests.swift \
  -o "$TEST_DIR/pager-mask-tests"
"$TEST_DIR/pager-mask-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/pager-mask-tests" "$CRA_TEST_KEEP/"
