#!/bin/bash
# Builds the CEF binary distribution Cra ships, from source, with H.264/AAC.
#
# Spotify's prebuilt CEF (cef-builds.spotifycdn.com) leaves proprietary codecs out,
# so MP4/HLS video (X, Instagram, Reddit, most news sites) never plays. Codecs are a
# compile-time switch in Chromium and FFmpeg is linked into the framework, so the
# only fix is building CEF ourselves with proprietary_codecs + ffmpeg_branding=Chrome.
#
# Builds the CEF_VERSION pinned in scripts/fetch-cef.sh (or the one in the environment;
# scripts/update-cef.sh does that); besides the codecs only the fixes in
# scripts/cef-patches/ change. Needs ~80 GB free and several hours on an M2 Max.
# Re-running resumes: the checkout is kept and ninja only rebuilds what changed.
#
# Output: $CEF_BUILD_DIR/chromium/src/cef/binary_distrib/cef_binary_<ver>_<arch>_minimal.tar.bz2
# Publish it with scripts/publish-cef.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

eval "$(grep -E '^CEF_VERSION=' scripts/fetch-cef.sh)"
# 154.0.34+g14c5a08+chromium-154.0.8037.98: CEF commit 14c5a08 on branch 8037.
CEF_COMMIT="$(sed -E 's/.*\+g([0-9a-f]+)\+.*/\1/' <<<"$CEF_VERSION")"
CEF_BRANCH="$(sed -E 's/.*chromium-[0-9]+\.[0-9]+\.([0-9]+)\..*/\1/' <<<"$CEF_VERSION")"
# Build for the host CPU by default (automate-git/make_distrib take --arm64-build /
# --x86-build); CEF_TARGET_ARCH (arm64 / x86) overrides.
CEF_TARGET_ARCH="${CEF_TARGET_ARCH:-$([ "$(uname -m)" = arm64 ] && echo arm64 || echo x86)}"
ARCH_FLAG="--${CEF_TARGET_ARCH}-build"
echo "Building CEF $CEF_VERSION (branch $CEF_BRANCH, commit $CEF_COMMIT, $CEF_TARGET_ARCH)"
# .noindex keeps Spotlight out of ~40 GB of sources.
CEF_BUILD_DIR="${CEF_BUILD_DIR:-$HOME/cef-build.noindex}"

# ANGLE compiles Metal shaders; Xcode 26 ships the Metal toolchain separately.
xcrun metal --version >/dev/null 2>&1 || xcodebuild -downloadComponent MetalToolchain

mkdir -p "$CEF_BUILD_DIR"
tmutil addexclusion "$CEF_BUILD_DIR" 2>/dev/null || true

if [ ! -d "$CEF_BUILD_DIR/depot_tools" ]; then
  git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git "$CEF_BUILD_DIR/depot_tools"
fi
# Bootstrap once (python, gn); DEPOT_TOOLS_UPDATE=0 below keeps it from updating.
[ -f "$CEF_BUILD_DIR/depot_tools/python3_bin_reldir.txt" ] || "$CEF_BUILD_DIR/depot_tools/ensure_bootstrap" || true
# automate-git.py from the branch being built (it changes between branches).
AUTOMATE="$CEF_BUILD_DIR/automate/$CEF_BRANCH/automate-git.py"
if [ ! -f "$AUTOMATE" ]; then
  mkdir -p "$(dirname "$AUTOMATE")"
  rm -rf "$CEF_BUILD_DIR/cef-tools"
  git -C "$CEF_BUILD_DIR" clone --depth 1 --branch "$CEF_BRANCH" https://github.com/chromiumembedded/cef.git cef-tools
  cp "$CEF_BUILD_DIR/cef-tools/tools/automate/automate-git.py" "$AUTOMATE"
  rm -rf "$CEF_BUILD_DIR/cef-tools"
fi

export PATH="$CEF_BUILD_DIR/depot_tools:$PATH"
export DEPOT_TOOLS_UPDATE=0
export CEF_ARCHIVE_FORMAT=tar.bz2
# symbol_level=0: full debug info would need another ~50 GB and is never shipped.
export GN_DEFINES="is_official_build=true proprietary_codecs=true ffmpeg_branding=Chrome symbol_level=0 blink_symbol_level=0 v8_symbol_level=0 enable_dsyms=false"

automate() {
  python3 "$AUTOMATE" \
    --download-dir="$CEF_BUILD_DIR" \
    --depot-tools-dir="$CEF_BUILD_DIR/depot_tools" \
    --branch="$CEF_BRANCH" \
    --checkout="$CEF_COMMIT" \
    "$ARCH_FLAG" \
    --no-chromium-history \
    --no-depot-tools-update \
    --with-pgo-profiles \
    --no-debug-build \
    --minimal-distrib-only \
    "$@"
}

PATCHES="$PWD/scripts/cef-patches"
cd "$CEF_BUILD_DIR"
# 1. Check out Chromium + CEF and apply CEF's own patches.
automate --no-build --no-distrib
# 2. Cra's Chromium fixes on top (skipped when already applied).
for p in "$PATCHES"/*.patch; do
  if git -C chromium/src apply --check "$p" 2>/dev/null; then
    git -C chromium/src apply "$p" && echo "Applied $(basename "$p")"
  else
    git -C chromium/src apply --check --reverse "$p" || { echo "$(basename "$p") does not apply" >&2; exit 1; }
  fi
done
# 3. Build without touching the checkout again.
automate --no-update --force-build --no-distrib
# 4. Package. automate-git does not pass --no-symbols on for branches after 7151,
#    and without dSYMs (enable_dsyms=false) make_distrib then fails.
rm -rf chromium/src/cef/binary_distrib
(cd chromium/src/cef/tools && python3 make_distrib.py --output-dir=../binary_distrib --allow-partial \
  --ninja-build "$ARCH_FLAG" --minimal --no-docs --no-symbols)
