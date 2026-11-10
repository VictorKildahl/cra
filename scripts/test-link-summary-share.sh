#!/bin/bash
# 5-Second Previews' Copy as Image (LinkSummaryShareImage) against Arc's own copy.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-link-summary-share.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/LinkSummaryCard.swift Sources/Cra/UI/LinkSummaryShareImage.swift \
  Tests/LinkSummaryShareImageTests.swift -o "$TEST_DIR/link-summary-share-tests"
"$TEST_DIR/link-summary-share-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/link-summary-share-tests" "$CRA_TEST_KEEP/"
