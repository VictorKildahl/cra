#!/bin/bash
# Right-click or hold Back or Forward (#416): the history menu's view and window off screen, and
# the button's hold. CRA_BACK_FORWARD_MENU_SNAPSHOT=<png> also draws the menu there.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-back-forward-menu-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/BackForwardMenu.swift \
  Sources/Cra/UI/Sidebar/SidebarCreationMenu.swift \
  Sources/Cra/UI/BackForwardMenuView.swift \
  Sources/Cra/UI/ButtonHold.swift \
  Tests/BackForwardMenuViewTests.swift \
  -o "$TEST_DIR/back-forward-menu-tests"
"$TEST_DIR/back-forward-menu-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/back-forward-menu-tests" "$CRA_TEST_KEEP/"
