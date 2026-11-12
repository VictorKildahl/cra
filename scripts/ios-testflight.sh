#!/bin/bash
# Archives the iPhone app (Release, signed for team 673A7J2J54) and uploads it to App Store
# Connect, where it shows up in TestFlight after Apple's processing (10–30 minutes).
#
#   scripts/ios-testflight.sh            # archive and upload
#   scripts/ios-testflight.sh --no-upload  # archive and export an .ipa into build/ios-export only
#
# Signing and the upload use either the Apple ID signed in to Xcode (Settings ▸ Accounts) or,
# when these are set, an App Store Connect API key (Users and Access ▸ Integrations ▸ Keys,
# role App Manager or Admin):
#   ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXX.p8 ASC_KEY_ID=XXXX ASC_ISSUER_ID=…
# The app record (bundle id dk.kildahl.cra) has to exist in App Store Connect first.
# The build number is the commit count, so every upload from a newer commit is accepted.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM="673A7J2J54"
ARCHIVE="build/ios-archive/Cra.xcarchive"
EXPORT="build/ios-export"
BUILD_NUMBER="$(git rev-list --count HEAD)"
destination="upload"
[ "${1:-}" = "--no-upload" ] && destination="export"

auth=(-allowProvisioningUpdates)
if [ -n "${ASC_KEY_PATH:-}" ]; then
  auth+=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "${ASC_KEY_ID:?}" -authenticationKeyIssuerID "${ASC_ISSUER_ID:?}")
fi

rm -rf "$ARCHIVE" "$EXPORT"
echo "archiving build $BUILD_NUMBER…"
xcodebuild -project iOS/Cra.xcodeproj -scheme Cra -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" "${auth[@]}" archive 2>&1 |
  grep -E "error|ARCHIVE (SUCCEEDED|FAILED)" || true
[ -d "$ARCHIVE" ] || { echo "archive failed" >&2; exit 1; }

options="$(mktemp -t cra-export).plist"
trap 'rm -f "$options"' EXIT
cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$destination</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>testFlightInternalTestingOnly</key><false/>
</dict>
</plist>
PLIST

echo "exporting ($destination)…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$options" "${auth[@]}" 2>&1 |
  grep -E "error|Upload|EXPORT (SUCCEEDED|FAILED)|Progress" || true
if [ "$destination" = "upload" ]; then
  echo "uploaded build $BUILD_NUMBER: it appears under TestFlight once Apple has processed it"
else
  ls "$EXPORT"/*.ipa
fi
