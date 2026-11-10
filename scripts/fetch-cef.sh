#!/bin/bash
# Downloads the pinned CEF binary distribution into vendor/cef (CEF_DIR overrides) and
# builds the C++ wrapper library. Safe to re-run; skips what is already there.
# scripts/build.sh puts the other CPU's copy in vendor/cef-<arch> (CRA_ARCH).
#
# Cra ships its own CEF build (scripts/build-cef.sh: H.264/AAC plus the fixes in
# scripts/cef-patches), published as a GitHub release asset by scripts/publish-cef.sh.
# CEF_URL=https://cef-builds.spotifycdn.com/<name>.tar.bz2 fetches Spotify's stock
# build instead (no H.264/AAC).
set -euo pipefail
cd "$(dirname "$0")/.."

CEF_VERSION="${CEF_VERSION:-156.0.27+ga10dae3+chromium-156.0.8078.96}"
# Follow the host CPU by default (macosarm64 / macosx64); CEF_ARCH overrides.
# Note: Spotify's CEF builds index names the Intel platform "macosx64".
ARCH="${CEF_ARCH:-$([ "$(uname -m)" = arm64 ] && echo macosarm64 || echo macosx64)}"
NAME="cef_binary_${CEF_VERSION}_${ARCH}_minimal"
# Bump the suffix (codecs2, …) when the build changes but CEF_VERSION does not.
CEF_RELEASE="${CEF_RELEASE:-cef-${CEF_VERSION%%+*}-codecs1}"
DIR="${CEF_DIR:-vendor/cef}"
URL="${CEF_URL:-https://github.com/VictorKildahl/cra/releases/download/${CEF_RELEASE}/cef_binary_${ARCH}_minimal.tar.bz2}"

mkdir -p "$(dirname "$DIR")"
# A different pinned build replaces the folder.
[ -d "$DIR/Release" ] && [ ! -f "$DIR/.cra-source" ] && echo "https://cef-builds.spotifycdn.com/${NAME}.tar.bz2" > "$DIR/.cra-source"
if [ -d "$DIR/Release" ] && [ "$(cat "$DIR/.cra-source")" != "$URL" ]; then
  echo "CEF build changed, replacing $DIR"
  rm -rf "$DIR"
fi
if [ ! -d "$DIR/Release" ]; then
  echo "Downloading ${NAME} from ${URL%/*}..."
  rm -rf "$DIR-download"
  mkdir -p "$DIR-download"
  python3 scripts/download-cef.py "$URL" "$DIR-download/${NAME}.tar.bz2"
  tar -xjf "$DIR-download/${NAME}.tar.bz2" -C "$DIR-download"
  rm -rf "$DIR"
  mv "$DIR-download/${NAME}" "$DIR"
  rm -rf "$DIR-download"
  echo "$URL" > "$DIR/.cra-source"
fi

if [ ! -f "$DIR/build/libcef_dll_wrapper/libcef_dll_wrapper.a" ]; then
  echo "Building libcef_dll_wrapper..."
  case "$ARCH" in
    macosarm64) TARGET_ARCH=arm64 ;;
    *)          TARGET_ARCH=x86_64 ;;
  esac
  cmake -S "$DIR" -B "$DIR/build" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH="$TARGET_ARCH" -DUSE_SANDBOX=ON \
    -DCMAKE_OSX_ARCHITECTURES="$TARGET_ARCH" > "$DIR/build-configure.log"
  cmake --build "$DIR/build" --target libcef_dll_wrapper -j "$(sysctl -n hw.ncpu)" > "$DIR/build-wrapper.log"
fi

# Chromium encrypts cookies, passwords and card numbers with a secret from the login
# Keychain item "Chromium Safe Storage", which every Chromium-based app without its own
# name shares. Cra's is "Cra Safe Storage" (SafeStorage.swift creates it before Chromium
# starts; scripts/cef-patches/keychain-service-name.patch renames it in CEF builds).
# cef-156.0.14-codecs2 predates that patch, so its framework is patched here: the name
# in os_crypt's constant pool, and the length (21) the compiler folded into both places
# that copy it into a std::string. Any other build must come with the source patch.
# Stop rather than ship a framework that looks for the old item: Cra would encrypt with
# one secret and Chromium decrypt with another.
FRAMEWORK_BIN="$DIR/Release/Chromium Embedded Framework.framework/Chromium Embedded Framework"
# Stock CEF builds (CEF_URL to spotifycdn.com) still use the shared "Chromium Safe
# Storage" item, and this binary patch is arm64-specific (the folded-length stores are
# ARM mov immediates). CRA_ALLOW_STOCK_CEF=1 accepts that: cookies and passwords are
# still encrypted, under the item every unpatched Chromium-based app shares.
if [ "${CRA_ALLOW_STOCK_CEF:-0}" = 1 ]; then
  if LC_ALL=C grep -qa "Chromium Safe Storage" "$FRAMEWORK_BIN"; then
    echo "CRA_ALLOW_STOCK_CEF=1: keeping the shared 'Chromium Safe Storage' Keychain item" >&2
  fi
else
  if LC_ALL=C grep -qa "Chromium Safe Storage" "$FRAMEWORK_BIN"; then
    if [ "$(shasum -a 256 "$FRAMEWORK_BIN" | cut -d' ' -f1)" != a910874407a9064fb6a944b2ffa0f86d9b5e1ea0a790608e8febea8d4949c7be ]; then
      echo "This CEF build still uses Chromium Safe Storage; build it with scripts/cef-patches" >&2
      exit 1
    fi
    patch_at() { printf "$2" | dd of="$FRAMEWORK_BIN" bs=1 seek=$(($1)) conv=notrunc status=none; }
    patch_at 0xc4fcaa1 'Cra Safe Storage\000\000\000\000\000'  # was "Chromium Safe Storage"
    patch_at 0x215fe50 '\011\002\200\122'                      # mov w9, #16 (was #21)
    patch_at 0x215ff8c '\010\002\200\122'                      # mov w8, #16 (was #21)
    echo "Renamed the Keychain item to Cra Safe Storage"
  fi
  LC_ALL=C grep -qa "Cra Safe Storage" "$FRAMEWORK_BIN" || { echo "CEF names no Cra Safe Storage" >&2; exit 1; }
fi
echo "CEF ready: $DIR"
