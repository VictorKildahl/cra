#!/bin/bash
# KeyBindingRegistry's command list: built-in actions, live folder plugin commands and the user's
# shortcuts, on a keybindings.json of its own (CRA_DATA_DIR). No window or CEF.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-key-bindings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/*.swift Packages/CraCore/Sources/CraCore/Perf/*.swift Sources/Cra/Perf/Perf.swift \
  Sources/Cra/App/KeyBindings.swift Sources/Cra/Services/KeyboardLayoutCharacters.swift \
  Sources/Cra/Services/Persistence.swift Sources/Cra/Services/CraLog.swift \
  Tests/KeyBindingsTests.swift -o "$TEST_DIR/key-binding-tests"
mkdir -p "$TEST_DIR/data"
CRA_DATA_DIR="$TEST_DIR/data" "$TEST_DIR/key-binding-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/key-binding-tests" "$CRA_TEST_KEEP/"
