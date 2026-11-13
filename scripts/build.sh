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
#   CRA_ARCH=x86_64 scripts/build.sh
#                               builds for the other CPU (arm64 or x86_64) into
#                               build/<arch>/Cra.app, with that CPU's CEF in
#                               vendor/cef-<arch> and SwiftPM's files in build/swiftpm-<arch>
# Cra runs on Chrome's own framework with Cra's layer (docs/chromium-engine.md), the engine
# scripts/fetch-engine.sh downloads into vendor/engine (vendor/engine-<arch> for the other CPU).
#   CRA_ENGINE_OUT=~/chromium.noindex/src/out/Cra_arm64 scripts/build.sh
#                               takes the engine from a local scripts/build-chromium.sh build instead
#   CRA_ENGINE=cef scripts/build.sh
#                               builds on CEF (vendor/cef, scripts/fetch-cef.sh), as before the switch
#   CRA_ENGINE_TEST=1           a test app of its own (dk.kildahl.cra.engine, executable CraEngine,
#                               build/engine/Cra.app) that never meets an installed Cra
# Dev builds are version 0.0.0-dev and stay unregistered with LaunchServices, so
# opening Cra (or a cra:// link) always picks the installed release.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
CONFIG="${1:-release}"
VERSION="${CRA_VERSION:-0.0.0-dev}"
BUILD_NUMBER="${CRA_BUILD:-$(date +%Y%m%d%H%M)}"

# The host CPU keeps the usual paths; the other one gets its own CEF, SwiftPM folder and
# app, so building it never replaces vendor/cef (worktrees share it) or build/Cra.app.
# scripts/release.sh finds the app with the same rule.
ARCH="${CRA_ARCH:-$(uname -m)}"
case "$ARCH" in
  arm64)  CEF_PLATFORM=macosarm64 ;;
  x86_64) CEF_PLATFORM=macosx64 ;;
  *) echo "CRA_ARCH must be arm64 or x86_64, not $ARCH" >&2; exit 1 ;;
esac
if [ "$ARCH" = "$(uname -m)" ]; then
  CEF_DIR=vendor/cef
  FINAL_APP="$ROOT/build/Cra.app"
  SWIFT_ARGS=(-c "$CONFIG")
else
  CEF_DIR="vendor/cef-$ARCH"
  FINAL_APP="$ROOT/build/$ARCH/Cra.app"
  SWIFT_ARGS=(-c "$CONFIG" --arch "$ARCH" --scratch-path "$ROOT/build/swiftpm-$ARCH")
  export CRA_CEF_DIR="$ROOT/$CEF_DIR"  # read by Package.swift
fi
ENGINE="${CRA_ENGINE:-chromium}"
EXE=Cra
if [ "$ENGINE" = chromium ]; then
  ENGINE_CPU=$([ "$ARCH" = x86_64 ] && echo x64 || echo arm64)
  if [ -n "${CRA_ENGINE_OUT:-}" ]; then
    FRAMEWORKS="$CRA_ENGINE_OUT/Cra.app/Contents/Frameworks"
  else
    ENGINE_DIR="vendor/engine$([ "$ARCH" = "$(uname -m)" ] || echo "-$ARCH")"
    ENGINE_DIR="$ENGINE_DIR" ENGINE_CPU="$ENGINE_CPU" scripts/fetch-engine.sh
    FRAMEWORKS="$ROOT/$ENGINE_DIR"
  fi
  export CRA_ENGINE=chromium CRA_ENGINE_FRAMEWORKS="$FRAMEWORKS"  # read by Package.swift
  [ -d "$CRA_ENGINE_FRAMEWORKS/Cra Framework.framework" ] || { echo "No engine in $FRAMEWORKS" >&2; exit 1; }
  # Its own SwiftPM folder: Package.swift differs between the engines.
  SWIFT_ARGS=(-c "$CONFIG" --arch "$ARCH" --scratch-path "$ROOT/build/swiftpm-engine-$ARCH")
  if [ "${CRA_ENGINE_TEST:-}" = 1 ]; then
    FINAL_APP="$ROOT/build/engine$([ "$ARCH" = "$(uname -m)" ] || echo "-$ARCH")/Cra.app"
    EXE=CraEngine
  fi
else
  CEF_DIR="$CEF_DIR" CEF_ARCH="$CEF_PLATFORM" scripts/fetch-cef.sh
fi
scripts/fetch-sparkle.sh

swift build "${SWIFT_ARGS[@]}"
BIN="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"

# Stage the bundle, then sync it into place so the existing Cra.app directory
# keeps its identity (LaunchServices otherwise launches duplicate instances).
STAGE="$(mktemp -d /tmp/cra-stage.XXXXXX)"
APP="$STAGE/Cra.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN/Cra" "$APP/Contents/MacOS/$EXE"
cp "$BIN/CraPluginHost" "$APP/Contents/MacOS/CraPluginHost"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" resources/Info.plist > "$APP/Contents/Info.plist"
# CRA_BUNDLE_ID builds under another identifier: a test build signed with one's own team and
# a provisioning profile for it (docs/release.md, "iCloud sync"). The data folder stays Cra's,
# so run such a build with CRA_DATA_DIR.
[ -n "${CRA_BUNDLE_ID:-}" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $CRA_BUNDLE_ID" "$APP/Contents/Info.plist"
# Only release builds (scripts/release.sh) check the update feed; a dev build would
# otherwise replace itself with the latest release. Intel copies have their own feed,
# since each update archive holds one CPU's app (scripts/appcast.sh).
[ "$ARCH" = x86_64 ] && /usr/libexec/PlistBuddy -c "Set :SUFeedURL https://github.com/VictorKildahl/cra/releases/latest/download/appcast-intel.xml" "$APP/Contents/Info.plist"
[ "${CRA_RELEASE:-}" = 1 ] || /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$APP/Contents/Info.plist"
# Google API key for Safe Browsing (docs/release.md); CraCEF hands it to Chromium.
[ -n "${CRA_GOOGLE_API_KEY:-}" ] && /usr/libexec/PlistBuddy -c "Add :CraGoogleAPIKey string $CRA_GOOGLE_API_KEY" "$APP/Contents/Info.plist"
if [ "$EXE" = CraEngine ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dk.kildahl.cra.engine" -c "Set :CFBundleExecutable $EXE" "$APP/Contents/Info.plist"
fi
echo -n "APPL????" > "$APP/Contents/PkgInfo"
[ -f resources/AppIcon.icns ] && cp resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The AppleScript dictionary (Arc's, same terms and codes: Info.plist OSAScriptingDefinition).
cp resources/Cra.sdef "$APP/Contents/Resources/Cra.sdef"
[ -d resources/web ] && cp -R resources/web "$APP/Contents/Resources/web"
[ -d resources/brand ] && cp -R resources/brand "$APP/Contents/Resources/brand"
[ -d resources/blocklist ] && cp -R resources/blocklist "$APP/Contents/Resources/blocklist"
[ -d resources/browsers ] && cp -R resources/browsers "$APP/Contents/Resources/browsers"
[ -d resources/app-icons ] && cp -R resources/app-icons "$APP/Contents/Resources/app-icons"
[ -d resources/licenses ] && cp -R resources/licenses "$APP/Contents/Resources/licenses"
[ -d resources/fonts ] && cp -R resources/fonts "$APP/Contents/Resources/fonts"
cp -R resources/live-folder-plugins "$APP/Contents/Resources/live-folder-plugins"

if [ "$ENGINE" = chromium ]; then
  FW_NAME="Cra Framework"
  ditto "$CRA_ENGINE_FRAMEWORKS/$FW_NAME.framework" "$APP/Contents/Frameworks/$FW_NAME.framework"
else
  FW_NAME="Chromium Embedded Framework"
  cp -R "$ROOT/$CEF_DIR/Release/$FW_NAME.framework" "$APP/Contents/Frameworks/"
fi
# Sparkle's XPC services are only for sandboxed apps; Cra uses Autoupdate and Updater.app.
ditto "$ROOT/vendor/sparkle/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

# CEF needs one helper app per process type (see cef_variables.cmake,
# CEF_HELPER_APP_SUFFIXES). Format: "<name suffix>|<plist suffix>".
# Chrome's framework has its own helpers inside it (Versions/<version>/Helpers).
[ "$ENGINE" = chromium ] || for entry in "|" " (Alerts)|.alerts" " (GPU)|.gpu" " (Plugin)|.plugin" " (Renderer)|.renderer"; do
  NAME_SUFFIX="${entry%%|*}"
  PLIST_SUFFIX="${entry#*|}"
  HELPER="$APP/Contents/Frameworks/Cra Helper${NAME_SUFFIX}.app"
  mkdir -p "$HELPER/Contents/MacOS"
  cp "$BIN/CraHelper" "$HELPER/Contents/MacOS/Cra Helper${NAME_SUFFIX}"
  sed -e "s/__NAME_SUFFIX__/${NAME_SUFFIX}/g" -e "s/__PLIST_SUFFIX__/${PLIST_SUFFIX}/g" \
      -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
      resources/Helper-Info.plist > "$HELPER/Contents/Info.plist"
  echo -n "APPL????" > "$HELPER/Contents/PkgInfo"
  # Chromium posts page notifications from the Alerts helper too, so macOS asks for it and lists
  # it under System Settings ▸ Notifications: Cra's name and icon there, like Arc's helper.
  if [ "$NAME_SUFFIX" = " (Alerts)" ]; then
    mkdir -p "$HELPER/Contents/Resources"
    cp resources/AppIcon.icns "$HELPER/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Cra" -c "Add :CFBundleIconFile string AppIcon" \
      -c "Add :NSUserNotificationAlertStyle string alert" "$HELPER/Contents/Info.plist"
  fi
done

# The Dock tile plug-in (Info.plist NSDockTilePlugIn), a SwiftPM dynamic library in a bundle.
DOCK_TILE="$APP/Contents/PlugIns/CraDockTile.docktileplugin"
mkdir -p "$DOCK_TILE/Contents/MacOS"
cp "$BIN/libCraDockTile.dylib" "$DOCK_TILE/Contents/MacOS/CraDockTile"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" resources/DockTile-Info.plist > "$DOCK_TILE/Contents/Info.plist"

# Every executable must run on the CPU this build is for (Sparkle ships universal).
for exe in "$APP/Contents/MacOS/$EXE" "$APP/Contents/MacOS/CraPluginHost" "$APP"/Contents/Frameworks/*.app/Contents/MacOS/* \
           "$DOCK_TILE/Contents/MacOS/CraDockTile" \
           "$APP/Contents/Frameworks/$FW_NAME.framework/$FW_NAME" \
           "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"; do
  [ -e "$exe" ] || continue
  lipo "$exe" -verify_arch "$ARCH" || { echo "$exe has no $ARCH code: $(lipo -archs "$exe")" >&2; exit 1; }
done

# Helpers link the framework at launch (Sources/CraHelper/main.cc says why: ~12 MB less in each
# page, GPU and utility process). The path has to resolve inside the bundle or no page starts.
if [ "$ENGINE" = cef ]; then
HELPER_EXE="$APP/Contents/Frameworks/Cra Helper.app/Contents/MacOS/Cra Helper"
FW_LINK="$(otool -L "$HELPER_EXE" | grep -o '@executable_path/.*Chromium Embedded Framework' || true)"
[ -n "$FW_LINK" ] && [ -f "$(dirname "$HELPER_EXE")/${FW_LINK#@executable_path/}" ] ||
  { echo "Cra Helper doesn't link the framework at launch (${FW_LINK:-no load command})" >&2; exit 1; }
fi

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
FW="$APP/Contents/Frameworks/$FW_NAME.framework"
find "$FW/Libraries" -name '*.dylib' -print0 2>/dev/null | while IFS= read -r -d '' lib; do sign "$lib"; done
if [ "$ENGINE" = chromium ]; then
  # Chrome's helpers and tools inside the framework, before the framework itself.
  for h in "$FW"/Versions/Current/Helpers/*; do
    case "$h" in
      *.app) sign "$h" "$ROOT/resources/CraHelper.entitlements" ;;  # pages, GPU, utilities: JIT and devices
      *) sign "$h" ;;                                               # crashpad handler, app-mode loader
    esac
  done
fi
sign "$FW"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign "$APP/Contents/MacOS/CraPluginHost"
for h in "$APP"/Contents/Frameworks/*.app; do if [ -e "$h" ]; then sign "$h" "$ROOT/resources/CraHelper.entitlements"; fi; done
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
  # iCloud sync (Settings ▸ General ▸ Sync) needs the container entitlements the profile grants
  # once iCloud Documents is on for the App ID. The first container is also named in Info.plist,
  # so the folder shows in iCloud Drive as "Cra".
  if CONTAINER="$($PB -c "Print :Entitlements:com.apple.developer.ubiquity-container-identifiers:0" "$PROFILE" 2>/dev/null)"; then
    for key in com.apple.developer.ubiquity-container-identifiers com.apple.developer.icloud-container-identifiers; do
      $PB -c "Add :$key array" "$APP_ENTITLEMENTS"
      i=0
      while id="$($PB -c "Print :Entitlements:com.apple.developer.ubiquity-container-identifiers:$i" "$PROFILE" 2>/dev/null)"; do
        $PB -c "Add :$key:$i string $id" "$APP_ENTITLEMENTS"
        i=$((i + 1))
      done
    done
    $PB -c "Add :com.apple.developer.icloud-services array" -c "Add :com.apple.developer.icloud-services:0 string CloudDocuments" "$APP_ENTITLEMENTS"
    # A Developer ID profile grants Development and Production; a distributed build uses
    # Production, as Xcode's Developer ID export claims it.
    if $PB -c "Print :Entitlements:com.apple.developer.icloud-container-environment" "$PROFILE" >/dev/null 2>&1; then
      $PB -c "Add :com.apple.developer.icloud-container-environment string Production" "$APP_ENTITLEMENTS"
    fi
    $PB -c "Add :NSUbiquitousContainers dict" -c "Add :NSUbiquitousContainers:$CONTAINER dict" \
        -c "Add :NSUbiquitousContainers:$CONTAINER:NSUbiquitousContainerIsDocumentScopePublic bool true" \
        -c "Add :NSUbiquitousContainers:$CONTAINER:NSUbiquitousContainerName string Cra" \
        -c "Add :NSUbiquitousContainers:$CONTAINER:NSUbiquitousContainerSupportedFolderLevels string Any" "$APP/Contents/Info.plist"
  else
    echo "Note: the provisioning profile grants no iCloud container; iCloud sync stays off" >&2
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
