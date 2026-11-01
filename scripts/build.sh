#!/bin/bash
# Builds Cra.app into build/Cra.app.
#   scripts/build.sh            release build, ad-hoc signed
#   scripts/build.sh debug      debug build
#   CRA_SIGN_IDENTITY="Developer ID Application: …" scripts/build.sh
#                               distributable build (see docs/release.md)
#   CRA_PROVISIONING_PROFILE=<path> (with CRA_SIGN_IDENTITY)
#                               adds the passkey entitlements the profile grants
#   CRA_INSTALL_DIR=<dir> scripts/build.sh
#                               also copies the app to <dir>/Cra.app
# Dev builds are version 0.0.0-dev and stay unregistered with LaunchServices, so
# opening Cra (or a cra:// link) always picks the installed release.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
CONFIG="${1:-release}"
VERSION="${CRA_VERSION:-0.0.0-dev}"
BUILD_NUMBER="${CRA_BUILD:-$(date +%Y%m%d%H%M)}"

scripts/fetch-cef.sh
scripts/fetch-sparkle.sh

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

# Stage the bundle, then sync it into place so the existing Cra.app directory
# keeps its identity (LaunchServices otherwise launches duplicate instances).
FINAL_APP="$ROOT/build/Cra.app"
STAGE="$(mktemp -d /tmp/cra-stage.XXXXXX)"
APP="$STAGE/Cra.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN/Cra" "$APP/Contents/MacOS/Cra"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" resources/Info.plist > "$APP/Contents/Info.plist"
# Only release builds (scripts/release.sh) check the update feed; a dev build would
# otherwise replace itself with the latest release.
[ "${CRA_RELEASE:-}" = 1 ] || /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$APP/Contents/Info.plist"
# Google API key for Safe Browsing (docs/release.md); CraCEF hands it to Chromium.
[ -n "${CRA_GOOGLE_API_KEY:-}" ] && /usr/libexec/PlistBuddy -c "Add :CraGoogleAPIKey string $CRA_GOOGLE_API_KEY" "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
[ -f resources/AppIcon.icns ] && cp resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[ -d resources/web ] && cp -R resources/web "$APP/Contents/Resources/web"
[ -d resources/brand ] && cp -R resources/brand "$APP/Contents/Resources/brand"
[ -d resources/blocklist ] && cp -R resources/blocklist "$APP/Contents/Resources/blocklist"
[ -d resources/browsers ] && cp -R resources/browsers "$APP/Contents/Resources/browsers"
[ -d resources/app-icons ] && cp -R resources/app-icons "$APP/Contents/Resources/app-icons"

FRAMEWORK_SRC="$ROOT/vendor/cef/Release/Chromium Embedded Framework.framework"
cp -R "$FRAMEWORK_SRC" "$APP/Contents/Frameworks/"
# Sparkle's XPC services are only for sandboxed apps; Cra uses Autoupdate and Updater.app.
ditto "$ROOT/vendor/sparkle/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

# CEF needs one helper app per process type (see cef_variables.cmake,
# CEF_HELPER_APP_SUFFIXES). Format: "<name suffix>|<plist suffix>".
for entry in "|" " (Alerts)|.alerts" " (GPU)|.gpu" " (Plugin)|.plugin" " (Renderer)|.renderer"; do
  NAME_SUFFIX="${entry%%|*}"
  PLIST_SUFFIX="${entry#*|}"
  HELPER="$APP/Contents/Frameworks/Cra Helper${NAME_SUFFIX}.app"
  mkdir -p "$HELPER/Contents/MacOS"
  cp "$BIN/CraHelper" "$HELPER/Contents/MacOS/Cra Helper${NAME_SUFFIX}"
  sed -e "s/__NAME_SUFFIX__/${NAME_SUFFIX}/g" -e "s/__PLIST_SUFFIX__/${PLIST_SUFFIX}/g" \
      -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
      resources/Helper-Info.plist > "$HELPER/Contents/Info.plist"
  echo -n "APPL????" > "$HELPER/Contents/PkgInfo"
done

# The Dock tile plug-in (Info.plist NSDockTilePlugIn), a SwiftPM dynamic library in a bundle.
DOCK_TILE="$APP/Contents/PlugIns/CraDockTile.docktileplugin"
mkdir -p "$DOCK_TILE/Contents/MacOS"
cp "$BIN/libCraDockTile.dylib" "$DOCK_TILE/Contents/MacOS/CraDockTile"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" resources/DockTile-Info.plist > "$DOCK_TILE/Contents/Info.plist"

# Code signing, innermost first. Ad-hoc by default; set CRA_SIGN_IDENTITY to a
# "Developer ID Application: …" identity for a distributable build with the
# hardened runtime, timestamps and the CEF entitlements. scripts/release.sh
# then notarizes the result.
IDENTITY="${CRA_SIGN_IDENTITY:--}"
sign() {  # sign <path> [entitlements]
  local target="$1" ent="${2:-}"
  if [ "$IDENTITY" = "-" ]; then
    codesign --force --sign - "$target"
  else
    local args=(--force --sign "$IDENTITY" --options runtime --timestamp)
    [ -n "$ent" ] && args+=(--entitlements "$ent")
    codesign "${args[@]}" "$target"
  fi
}
FW="$APP/Contents/Frameworks/Chromium Embedded Framework.framework"
find "$FW/Libraries" -name '*.dylib' -print0 2>/dev/null | while IFS= read -r -d '' lib; do sign "$lib"; done
sign "$FW"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
for h in "$APP"/Contents/Frameworks/*.app; do sign "$h" "$ROOT/resources/CraHelper.entitlements"; done
sign "$DOCK_TILE"
# Passkeys need entitlements only a provisioning profile can grant: the Touch ID
# keychain group ("<app id>.webauthn", scripts/cef-patches) and, once Apple approves
# it, iCloud Keychain (web-browser.public-key-credential). With
# CRA_PROVISIONING_PROFILE=<Developer ID profile> the app embeds it and claims what
# it allows; macOS refuses to launch an app that claims more. See docs/release.md.
APP_ENTITLEMENTS="$ROOT/resources/Cra.entitlements"
if [ -n "${CRA_PROVISIONING_PROFILE:-}" ] && [ "$IDENTITY" != "-" ]; then
  PB=/usr/libexec/PlistBuddy
  PROFILE="$STAGE/profile.plist"
  security cms -D -i "$CRA_PROVISIONING_PROFILE" -o "$PROFILE"
  APP_ID="$($PB -c "Print :Entitlements:com.apple.application-identifier" "$PROFILE")"
  BUNDLE_ID="$($PB -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")"
  [ "${APP_ID#*.}" = "$BUNDLE_ID" ] || { echo "Provisioning profile is for $APP_ID, not $BUNDLE_ID" >&2; exit 1; }
  cp "$CRA_PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  APP_ENTITLEMENTS="$STAGE/Cra.entitlements"
  cp "$ROOT/resources/Cra.entitlements" "$APP_ENTITLEMENTS"
  $PB -c "Add :com.apple.application-identifier string $APP_ID" \
      -c "Add :com.apple.developer.team-identifier string ${APP_ID%%.*}" "$APP_ENTITLEMENTS"
  if $PB -c "Print :Entitlements:keychain-access-groups" "$PROFILE" >/dev/null 2>&1; then
    $PB -c "Add :keychain-access-groups array" -c "Add :keychain-access-groups:0 string $APP_ID.webauthn" "$APP_ENTITLEMENTS"
  fi
  if [ "$($PB -c "Print :Entitlements:com.apple.developer.web-browser.public-key-credential" "$PROFILE" 2>/dev/null)" = true ]; then
    $PB -c "Add :com.apple.developer.web-browser.public-key-credential bool true" "$APP_ENTITLEMENTS"
  else
    echo "Note: the provisioning profile has no web-browser.public-key-credential; iCloud Keychain passkeys stay off" >&2
  fi
fi
sign "$APP" "$APP_ENTITLEMENTS"
if [ "$IDENTITY" != "-" ]; then
  codesign --verify --deep --strict --verbose=2 "$APP"
fi

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
mkdir -p "$FINAL_APP"
rsync -a --delete "$APP/" "$FINAL_APP/"
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
rm -rf "$STAGE"
"$LSREGISTER" -u "$FINAL_APP" >/dev/null 2>&1 || true
echo "Built $FINAL_APP"

# Optional copy outside ~/Documents (an app that runs from Documents makes macOS ask
# for folder access and blocks the main thread until answered).
if [ -n "${CRA_INSTALL_DIR:-}" ]; then
  INSTALL_APP="$CRA_INSTALL_DIR/Cra.app"
  mkdir -p "$CRA_INSTALL_DIR"
  rsync -a --delete "$FINAL_APP/" "$INSTALL_APP/"
  "$LSREGISTER" -u "$INSTALL_APP" >/dev/null 2>&1 || true
  echo "Installed $INSTALL_APP"
fi
