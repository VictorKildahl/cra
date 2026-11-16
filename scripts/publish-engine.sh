#!/bin/bash
# Publishes the engine built by scripts/build-chromium.sh (Cra Framework.framework, with its helpers) as a GitHub
# release asset, where scripts/fetch-engine.sh (and CI) download it from. A pre-release, so releases/latest keeps
# pointing at the newest Cra.
#   scripts/publish-engine.sh              this Mac's CPU
#   ENGINE_CPU=x64 scripts/publish-engine.sh   the Intel build, into the same release
set -euo pipefail
cd "$(dirname "$0")/.."

eval "$(grep -E '^(ENGINE_VERSION|ENGINE_RELEASE|CPU)=' scripts/fetch-engine.sh)"
ROOT="${CHROMIUM_ROOT:-$HOME/chromium.noindex}"
FW="$ROOT/src/out/Cra_$CPU/Cra.app/Contents/Frameworks/Cra Framework.framework"
[ -d "$FW" ] || { echo "No engine at $FW; run scripts/build-chromium.sh" >&2; exit 1; }
built="$(cat "$ROOT/.cra-tag" 2>/dev/null || true)"
[ -z "$built" ] || [ "$built" = "$ENGINE_VERSION" ] || { echo "The tree is Chrome $built, fetch-engine.sh pins $ENGINE_VERSION" >&2; exit 1; }

WORK="$(mktemp -d)"
ASSET="$WORK/cra_framework_${CPU}.tar.xz"
# Symlinks kept (the framework's Versions/Current), extended attributes left out.
COPYFILE_DISABLE=1 tar -C "$(dirname "$FW")" -cJf "$ASSET" "Cra Framework.framework"
NOTES="Cra's engine for macOS, one asset per CPU (arm64, x64): Chrome ${ENGINE_VERSION}'s framework with Cra's layer, Cra's patches and ungoogled-chromium's (engine/chromium), built by scripts/build-chromium.sh. Downloaded by scripts/fetch-engine.sh; not a Cra release."
if gh release view "$ENGINE_RELEASE" >/dev/null 2>&1; then
  gh release upload "$ENGINE_RELEASE" "$ASSET" --clobber
else
  gh release create "$ENGINE_RELEASE" "$ASSET" --prerelease --latest=false --title "Engine ${ENGINE_VERSION}" --notes "$NOTES"
fi
rm -rf "$WORK"
echo "Published $ENGINE_RELEASE ($CPU)"
