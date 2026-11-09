#!/bin/bash
# Folder emblems: real AppKit layer projection and bitmap pixels, without CEF or visible windows.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-folder-glyph.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cp -R resources/fonts "$TEST_DIR/fonts"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/FolderSymbol.swift Sources/Cra/UI/Sidebar/FolderSymbolImages.swift \
  Sources/Cra/UI/Sidebar/LiveFolderMarks.swift \
  Sources/Cra/UI/Sidebar/List/FolderGlyphView.swift Tests/FolderGlyphTests.swift \
  -o "$TEST_DIR/folder-glyph-tests"
"$TEST_DIR/folder-glyph-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/folder-glyph-tests" "$CRA_TEST_KEEP/"
