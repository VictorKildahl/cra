#!/bin/bash
# Easel canvas clicks: one click picks a text block, a double click edits it, Return/Escape end editing,
# Delete removes the picked block and its size pill follows a drag.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-easel-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/Easel.swift Packages/CraCore/Sources/CraCore/EaselResize.swift \
  Packages/CraCore/Sources/CraCore/SpaceTheme.swift Sources/Cra/UI/Easel/EaselCanvasView.swift \
  Tests/EaselCanvasSupport/AppServices.swift Tests/EaselCanvasTests.swift -o "$TEST_DIR/easel-tests"
"$TEST_DIR/easel-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/easel-tests" "$CRA_TEST_KEEP/"

mkdir -p "$TEST_DIR/bridge"
cp Tests/EaselCanvasSupport/BrowserBridge.h "$TEST_DIR/bridge/"
cp Sources/CraCEF/include/CraCEF.h "$TEST_DIR/bridge/"
printf 'module CraCEF { header "BrowserBridge.h" export * }\n' > "$TEST_DIR/bridge/module.modulemap"
xcrun clang -fobjc-arc -Wno-incomplete-implementation -Wno-protocol -Wno-objc-property-implementation \
  -I "$TEST_DIR/bridge" -c Tests/EaselCanvasSupport/BrowserBridge.m -o "$TEST_DIR/bridge.o"
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} -module-cache-path "$TEST_DIR/cache" -I "$TEST_DIR/bridge" \
  Packages/CraCore/Sources/CraCore/Easel.swift Packages/CraCore/Sources/CraCore/EaselResize.swift \
  Packages/CraCore/Sources/CraCore/SpaceTheme.swift Sources/Cra/UI/Easel/EaselCanvasView.swift \
  Sources/Cra/UI/Easel/EaselBrowser.swift Tests/EaselCanvasSupport/BrowserServices.swift \
  Tests/EaselBrowserTests.swift "$TEST_DIR/bridge.o" -o "$TEST_DIR/easel-browser-tests"
CRA_DATA_DIR="$TEST_DIR/data" "$TEST_DIR/easel-browser-tests"
