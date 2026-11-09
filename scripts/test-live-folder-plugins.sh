#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-live-folder-plugins.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 Sources/CraPluginHost/main.swift -framework JavaScriptCore -o "$TEST_DIR/CraPluginHost"
xcrun swiftc -swift-version 5 -parse-as-library \
  Packages/CraCore/Sources/CraCore/LiveFolderPlugin.swift \
  Packages/CraCore/Sources/CraCore/LiveFolderPluginPackage.swift \
  Packages/CraCore/Sources/CraCore/LiveFolderPluginOutput.swift \
  Packages/CraCore/Sources/CraCore/LiveFolderPluginProcess.swift \
  Tests/LiveFolderPluginProcessTests.swift -o "$TEST_DIR/plugin-tests"
"$TEST_DIR/plugin-tests" "$TEST_DIR/CraPluginHost"
