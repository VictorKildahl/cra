#!/bin/bash
# Downloads the pinned engine (Chrome's framework with Cra's layer and patches, built by
# scripts/build-chromium.sh and published by scripts/publish-engine.sh) into vendor/engine
# (ENGINE_DIR overrides; scripts/build.sh puts the other CPU's in vendor/engine-<arch>). Safe to re-run;
# skips what is already there. docs/chromium-engine.md says what the engine is.
set -euo pipefail
cd "$(dirname "$0")/.."

ENGINE_VERSION="${ENGINE_VERSION:-158.0.8127.37}"
# Bump the suffix when the build changes but the Chrome version does not.
ENGINE_RELEASE="${ENGINE_RELEASE:-engine-${ENGINE_VERSION}-2}"
CPU="${ENGINE_CPU:-$([ "$(uname -m)" = arm64 ] && echo arm64 || echo x64)}"
DIR="${ENGINE_DIR:-vendor/engine}"
URL="${ENGINE_URL:-https://github.com/VictorKildahl/cra/releases/download/${ENGINE_RELEASE}/cra_framework_${CPU}.tar.xz}"

if [ -d "$DIR/Cra Framework.framework" ] && [ "$(cat "$DIR/.cra-source" 2>/dev/null)" = "$URL" ]; then
  exit 0
fi
echo "Downloading the engine ${ENGINE_RELEASE} (${CPU})..."
rm -rf "$DIR-download"
mkdir -p "$DIR-download"
python3 scripts/download-cef.py "$URL" "$DIR-download/engine.tar.xz"
tar -xJf "$DIR-download/engine.tar.xz" -C "$DIR-download"
[ -d "$DIR-download/Cra Framework.framework" ] || { echo "No Cra Framework.framework in $URL" >&2; exit 1; }
rm -rf "$DIR"
mkdir -p "$DIR"
mv "$DIR-download/Cra Framework.framework" "$DIR/"
rm -rf "$DIR-download"
echo "$URL" > "$DIR/.cra-source"
