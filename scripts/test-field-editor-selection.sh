#!/bin/bash
# The command bar's address comes up selected from its start, not the end the field was scrolled to: a real NSTextField off screen, no CEF.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-field-editor-selection.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Sources/Cra/UI/CommandBar/FieldEditorSelection.swift Tests/FieldEditorSelectionTests.swift \
  -o "$TEST_DIR/field-editor-selection-tests"
"$TEST_DIR/field-editor-selection-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/field-editor-selection-tests" "$CRA_TEST_KEEP/"
