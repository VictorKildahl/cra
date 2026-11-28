#!/bin/bash
# scripts/ios-sdk-check.sh on stand-in app bundles: App Store 0.1.2 (build 1478) was linked against
# the iOS 26.5 SDK, so the iPhone Duo ran it in compatibility mode, with a black column beside every
# page on the closed screen and a phone-sized window on the open one (Discord #ideas, 27 Nov 2026).
# A build linked on 27.1 or newer passes; one whose app or extension is older is refused.
set -euo pipefail
cd "$(dirname "$0")/.."
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() { echo "ios-sdk-check: $*" >&2; exit 1; }

echo 'int main(void) { return 0; }' > "$T/main.c"
xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 -o "$T/binary" "$T/main.c"

# bundle <dir> <executable> <sdk>: a bundle whose executable says it was linked against <sdk>.
bundle() {
  mkdir -p "$1"
  vtool -set-build-version ios 17.0 "$3" -replace -output "$1/$2" "$T/binary"
  plutil -create xml1 "$1/Info.plist"
  plutil -insert CFBundleExecutable -string "$2" "$1/Info.plist"
}
check() { scripts/ios-sdk-check.sh "$T/Cra.app" > /dev/null 2>&1; }

# Build 1478: the app linked against the iOS 26.5 SDK.
bundle "$T/Cra.app" Cra 26.5
check && fail "an app linked against the iOS 26.5 SDK (App Store 0.1.2) passed"

# The Duo's own SDK and newer pass, extensions too.
bundle "$T/Cra.app" Cra 27.1
bundle "$T/Cra.app/PlugIns/CraWidgets.appex" CraWidgets 27.2
check || fail "an app linked against the iOS 27.1 SDK was refused"

# An extension left on an older SDK is refused, and named.
bundle "$T/Cra.app/PlugIns/CraShare.appex" CraShare 26.5
check && fail "an extension linked against the iOS 26.5 SDK passed"
said="$(scripts/ios-sdk-check.sh "$T/Cra.app" 2>&1 || true)"
[[ "$said" == *"CraShare.appex (iOS SDK 26.5)"* ]] || fail "the refusal didn't name the extension and its SDK: $said"

# Version order, not text order: 27.10 is newer than 27.1, 27.0 older.
bundle "$T/Cra.app/PlugIns/CraShare.appex" CraShare 27.10
check || fail "an extension linked against the iOS 27.10 SDK was refused"
bundle "$T/Cra.app" Cra 27.0
check && fail "an app linked against the iOS 27.0 SDK passed"

echo "iOS SDK check: builds linked before iOS 27.1 (compatibility mode on the iPhone Duo) aren't uploaded"
