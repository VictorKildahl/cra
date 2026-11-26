#!/bin/bash
# scripts/check-load-paths.sh on made-up apps (GitHub #720): a binary with an rpath into a toolchain and into Xcode 27's
# PackageFrameworks build folder, one in an Xcode
# with a space in its name and one whose name ends in "(GPU)" as Chrome's helpers do, are caught, and stripped they
# pass; @executable_path, /usr/lib/swift and the system's libraries pass as they are.
set -euo pipefail
cd "$(dirname "$0")/.."
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
echo 'int main(void) { return 0; }' > "$T/main.c"
APP="$T/Test.app/Contents"
mkdir -p "$APP/MacOS" "$APP/Frameworks/Helper (GPU).app/Contents/MacOS"
cc "$T/main.c" -o "$APP/MacOS/Test" -Wl,-rpath,@executable_path/../Frameworks -Wl,-rpath,/usr/lib/swift \
  -Wl,-rpath,/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx \
  -Wl,-rpath,/Users/runner/work/cra/cra/build/swiftpm-engine-arm64/out/Products/Debug/PackageFrameworks
cc "$T/main.c" -o "$APP/Frameworks/Helper (GPU).app/Contents/MacOS/Helper (GPU)" \
  -Wl,-rpath,"/Applications/Xcode 26.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-6.2/macosx"
fail() { echo "load paths: $*" >&2; exit 1; }

out="$(scripts/check-load-paths.sh "$T/Test.app" 2>&1)" && fail "a toolchain rpath passed the check"
grep -q 'MacOS/Test points outside the app: /Applications/Xcode.app/' <<<"$out" || fail "the app's toolchain rpath wasn't named: $out"
grep -q 'Helper (GPU) points outside the app: /Applications/Xcode 26.app/' <<<"$out" || fail "the helper's wasn't named in full: $out"
grep -q 'MacOS/Test points outside the app: /Users/runner/.*/PackageFrameworks' <<<"$out" || fail "Xcode 27's PackageFrameworks rpath wasn't named: $out"

scripts/check-load-paths.sh --strip "$APP/MacOS/Test" "$APP/Frameworks/Helper (GPU).app/Contents/MacOS/Helper (GPU)"
scripts/check-load-paths.sh "$T/Test.app" || fail "stripped, the app still fails the check"
otool -l "$APP/MacOS/Test" | grep -q '@executable_path/../Frameworks' || fail "the strip took the bundle's own rpath too"
echo "Load paths: toolchain and PackageFrameworks rpaths caught (spaces and (GPU) names too), stripped, the bundle's own kept"
