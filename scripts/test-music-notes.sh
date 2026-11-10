#!/bin/bash
# Note tint: real sprite pixels at 1x and 2x, without CEF or an on-screen window.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-music-notes.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/MusicNotes.swift Sources/Cra/UI/Sidebar/MusicNotesView.swift \
  Tests/MusicNotesViewTests.swift -o "$TEST_DIR/music-notes-tests"
"$TEST_DIR/music-notes-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/music-notes-tests" "$CRA_TEST_KEEP/"
