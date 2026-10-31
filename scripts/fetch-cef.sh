#!/bin/bash
# Downloads the pinned CEF binary distribution into vendor/cef and builds the
# C++ wrapper library. Safe to re-run; skips what is already there.
#
# Cra ships its own CEF build (scripts/build-cef.sh: H.264/AAC plus the fixes in
# scripts/cef-patches), published as a GitHub release asset by scripts/publish-cef.sh.
# CEF_URL=https://cef-builds.spotifycdn.com/<name>.tar.bz2 fetches Spotify's stock
# build instead (no H.264/AAC).
set -euo pipefail
cd "$(dirname "$0")/.."

CEF_VERSION="${CEF_VERSION:-156.0.15+gcf671c0+chromium-156.0.8078.80}"
ARCH="${CEF_ARCH:-macosarm64}"
NAME="cef_binary_${CEF_VERSION}_${ARCH}_minimal"
# Bump the suffix (codecs2, …) when the build changes but CEF_VERSION does not.
CEF_RELEASE="${CEF_RELEASE:-cef-${CEF_VERSION%%+*}-codecs1}"
URL="${CEF_URL:-https://github.com/VictorKildahl/cra/releases/download/${CEF_RELEASE}/cef_binary_${ARCH}_minimal.tar.bz2}"

mkdir -p vendor
# A different pinned build replaces vendor/cef.
[ -d vendor/cef/Release ] && [ ! -f vendor/cef/.cra-source ] && echo "https://cef-builds.spotifycdn.com/${NAME}.tar.bz2" > vendor/cef/.cra-source
if [ -d vendor/cef/Release ] && [ "$(cat vendor/cef/.cra-source)" != "$URL" ]; then
  echo "CEF build changed, replacing vendor/cef"
  rm -rf vendor/cef
fi
if [ ! -d vendor/cef/Release ]; then
  echo "Downloading ${NAME} from ${URL%/*}..."
  rm -rf vendor/cef-download
  mkdir -p vendor/cef-download
  curl -fL --progress-bar -o "vendor/cef-download/${NAME}.tar.bz2" "$URL"
  tar -xjf "vendor/cef-download/${NAME}.tar.bz2" -C vendor/cef-download
  rm -rf vendor/cef
  mv "vendor/cef-download/${NAME}" vendor/cef
  rm -rf vendor/cef-download
  echo "$URL" > vendor/cef/.cra-source
fi

if [ ! -f vendor/cef/build/libcef_dll_wrapper/libcef_dll_wrapper.a ]; then
  echo "Building libcef_dll_wrapper..."
  cmake -S vendor/cef -B vendor/cef/build -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH=arm64 -DUSE_SANDBOX=ON \
    -DCMAKE_OSX_ARCHITECTURES=arm64 > vendor/cef/build-configure.log
  cmake --build vendor/cef/build --target libcef_dll_wrapper -j "$(sysctl -n hw.ncpu)" > vendor/cef/build-wrapper.log
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
FRAMEWORK_BIN="vendor/cef/Release/Chromium Embedded Framework.framework/Chromium Embedded Framework"
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
echo "CEF ready: vendor/cef"
