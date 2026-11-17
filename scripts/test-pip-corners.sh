#!/bin/bash
# Picture in Picture hover controls stay inside the window's rounded corners: the real controls in an off-screen window, no CEF (#463).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-pip-corners.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library ${CRA_TEST_SWIFTC_FLAGS:-} \
  Sources/Cra/UI/PictureInPicture/PictureInPictureControls.swift \
  Packages/CraCore/Sources/CraCore/PictureInPictureLayout.swift Packages/CraCore/Sources/CraCore/PictureInPictureScrubber.swift Packages/CraCore/Sources/CraCore/PictureInPictureThrow.swift \
  Packages/CraCore/Sources/CraCore/PictureInPictureGesture.swift \
  Tests/PictureInPictureCornersTests.swift \
  -o "$TEST_DIR/pip-corners-tests"
"$TEST_DIR/pip-corners-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/pip-corners-tests" "$CRA_TEST_KEEP/"
