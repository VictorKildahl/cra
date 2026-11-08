#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-easel-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Packages/CraCore/Sources/CraCore/Easel.swift Packages/CraCore/Sources/CraCore/EaselResize.swift \
  Packages/CraCore/Sources/CraCore/SpaceTheme.swift Sources/Cra/UI/Easel/EaselCanvasView.swift \
  Tests/EaselCanvasSupport/AppServices.swift Tests/EaselCanvasTests.swift -o "$TEST_DIR/easel-tests"
"$TEST_DIR/easel-tests"
