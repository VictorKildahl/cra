#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp/}cra-creation-menu-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Sources/Cra/UI/Sidebar/SpaceDock.swift Sources/Cra/UI/Sidebar/SidebarCreationMenu.swift \
  Tests/SidebarCreationMenuTests.swift \
  -o "$TEST_DIR/creation-menu-tests"
"$TEST_DIR/creation-menu-tests"
