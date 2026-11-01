#!/bin/bash
# The command bar's leading glyph rule (CommandBarGlyph); no AppKit window or CEF.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d /tmp/cra-glyph-tests.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -parse-as-library Sources/Cra/UI/CommandBar/CommandBarGlyph.swift Tests/CommandBarGlyphTests.swift \
  -o "$TEST_DIR/glyph-tests"
"$TEST_DIR/glyph-tests"
