#!/bin/bash
# Native preview callback contract. Requires the installed CEF headers/wrapper; no Chromium boot.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cra-link-summary-cef.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
CEF_DIR="${CRA_CEF_DIR:-vendor/cef}"
if [ ! -f "$CEF_DIR/build/libcef_dll_wrapper/libcef_dll_wrapper.a" ]; then
  echo "Link summary CEF callback contract: skipped (CEF headers/wrapper not installed)"
  exit 0
fi
clang_flags=(-std=c++20)
for flag in ${CRA_TEST_SWIFTC_FLAGS:-}; do
  case "$flag" in
    -profile-generate) clang_flags+=(-fprofile-instr-generate) ;;
    -profile-coverage-mapping) clang_flags+=(-fcoverage-mapping) ;;
    -sanitize=*) clang_flags+=("-fsanitize=${flag#-sanitize=}") ;;
  esac
done
xcrun clang++ -fobjc-arc -fno-exceptions -fno-rtti -fno-threadsafe-statics \
  -Wno-unused-parameter -Wno-deprecated-declarations "${clang_flags[@]}" ${CRA_TEST_CLANG_FLAGS:-} \
  -I "$CEF_DIR" -I Sources/CraCEF -I Sources/CraCEF/include \
  Sources/CraCEF/CraPreviewFetch.mm Tests/LinkSummaryCEFFetchTests.mm \
  -L "$CEF_DIR/build/libcef_dll_wrapper" -lcef_dll_wrapper -framework Cocoa -o "$TEST_DIR/link-summary-cef-tests"
"$TEST_DIR/link-summary-cef-tests"
[ -z "${CRA_TEST_KEEP:-}" ] || cp "$TEST_DIR/link-summary-cef-tests" "$CRA_TEST_KEEP/"
