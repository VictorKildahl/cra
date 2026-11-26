#!/bin/bash
# ⌘Z in the command bar undoes what was typed past its inline completion (#809): a real NSTextField off screen, no CEF.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-field-typing-undo.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/TypingUndoSteps.swift Sources/Cra/UI/CommandBar/FieldTypingUndo.swift Tests/FieldTypingUndoTests.swift \
  -o "$TEST_DIR/field-typing-undo-tests"
"$TEST_DIR/field-typing-undo-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/field-typing-undo-tests" "$CRA_TEST_KEEP/"
