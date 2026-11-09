#!/bin/bash
# Live folder plugins: the real CraPluginHost (JavaScriptCore, sandboxed) and the bundled GitHub,
# GitLab and Jira providers, driven through LiveFolderPluginProcess with made-up session responses.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-live-folder-plugins.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 Sources/CraPluginHost/main.swift -framework JavaScriptCore -o "$TEST_DIR/CraPluginHost"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/LiveFolderPlugin.swift \
  Packages/CraCore/Sources/CraCore/LiveFolderPluginPackage.swift \
  Packages/CraCore/Sources/CraCore/LiveFolderPluginOutput.swift \
  Packages/CraCore/Sources/CraCore/LiveFolderPluginProcess.swift \
  Packages/CraCore/Sources/CraCore/LiveFolderPluginConfiguration.swift \
  Packages/CraCore/Sources/CraCore/LiveFolderModel.swift Packages/CraCore/Sources/CraCore/GitLabLiveClient.swift \
  Tests/LiveFolderPluginProcessTests.swift Tests/LiveFolderProviderTests.swift -o "$TEST_DIR/plugin-tests"
"$TEST_DIR/plugin-tests" "$TEST_DIR/CraPluginHost"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/plugin-tests" "$CRA_TEST_KEEP/"
