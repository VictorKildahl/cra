#!/bin/bash
# Writes build/dist/appcast.xml and appcast-stable.xml, the Sparkle feeds installed copies of Cra check every
# 8 hours (SUFeedURL: releases/latest/download/appcast.xml). Intel copies read
# appcast-intel.xml (scripts/build.sh), written when the app is the Intel one. The update archive is
# signed with the EdDSA key: SPARKLE_PRIVATE_KEY (CI secret), or the "cra" key in the
# login keychain (made once with vendor/sparkle/bin/generate_keys --account cra).
#   scripts/appcast.sh [Cra.zip] [Cra.app] [release-notes.html]
# CRA_UPDATE_URL overrides the download URL (tests point it at a local server).
# Channels (GitHub #476, docs/release.md): appcast$SUFFIX.xml also holds the Stable release and
# appcast-stable$SUFFIX.xml holds it alone (scripts/appcast-feeds.py). CRA_STABLE_FEED is an appcast holding
# Cra $CRA_STABLE_VERSION (scripts/release.sh fetches it); without one this release is Stable as well.
set -euo pipefail
cd "$(dirname "$0")/.."
ZIP="${1:-build/dist/Cra.zip}"
APP="${2:-build/Cra.app}"
NOTES="${3:-}"
SUFFIX="$(scripts/asset-suffix.sh "$APP")"
SUFFIX_LOWER="$(echo "$SUFFIX" | tr '[:upper:]' '[:lower:]')"
OUT_DIR="$(dirname "$ZIP")"
OUT="$(mktemp -d /tmp/cra-appcast.XXXXXX)/appcast.xml"

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }
VERSION="$(plist CFBundleShortVersionString)"
BUILD="$(plist CFBundleVersion)"
MIN_OS="$(plist LSMinimumSystemVersion)"
URL="${CRA_UPDATE_URL:-https://github.com/VictorKildahl/cra/releases/download/v$VERSION/$(basename "$ZIP")}"

SIGN=vendor/sparkle/bin/sign_update
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  ENCLOSURE="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN" --ed-key-file - "$ZIP")"
else
  ENCLOSURE="$("$SIGN" --account cra "$ZIP")"
fi

DESCRIPTION=""
if [ -n "$NOTES" ] && [ -f "$NOTES" ]; then
  DESCRIPTION="
      <description><![CDATA[$(cat "$NOTES")]]></description>"
fi

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Cra</title>
    <link>https://crabrowser.app/release-notes</link>
    <item>
      <title>Cra $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://crabrowser.app/release-notes</sparkle:fullReleaseNotesLink>$DESCRIPTION
      <enclosure url="$URL" type="application/octet-stream" $ENCLOSURE/>
    </item>
  </channel>
</rss>
XML
STABLE_FEED="${CRA_STABLE_FEED:-$OUT}"
STABLE_VERSION="${CRA_STABLE_VERSION:-$VERSION}"
[ -n "${CRA_STABLE_FEED:-}" ] && [ -z "${CRA_STABLE_VERSION:-}" ] && { echo "CRA_STABLE_FEED needs CRA_STABLE_VERSION" >&2; exit 1; }
python3 scripts/appcast-feeds.py "$OUT_DIR" "$SUFFIX_LOWER" "$OUT" "$VERSION" "$STABLE_FEED" "$STABLE_VERSION"
rm -rf "$(dirname "$OUT")"
echo "Feeds for Cra $VERSION (build $BUILD), Stable Cra $STABLE_VERSION"
