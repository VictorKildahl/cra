#!/bin/bash
# A space's emoji label as macOS 27 draws it (clipped to its frame, its cell's text cut at the baseline): real AppKit pixels, no CEF or window (#399).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-emoji-label.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Sources/Cra/UI/Sidebar/List/EmojiLabel.swift Tests/EmojiLabelTests.swift \
  -o "$TEST_DIR/emoji-label-tests"
"$TEST_DIR/emoji-label-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/emoji-label-tests" "$CRA_TEST_KEEP/"
