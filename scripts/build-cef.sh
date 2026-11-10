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
# The Chromium tag is passed to automate-git, so a CEF commit can also be built on a newer
# Chromium patch of its branch than CEF pins (an Extended Stable security update that CEF
# hasn't picked up yet): 156.0.27+ga10dae3+chromium-156.0.8078.96.
CEF_COMMIT="$(sed -E 's/.*\+g([0-9a-f]+)\+.*/\1/' <<<"$CEF_VERSION")"
CEF_BRANCH="$(sed -E 's/.*chromium-[0-9]+\.[0-9]+\.([0-9]+)\..*/\1/' <<<"$CEF_VERSION")"
# Builds for the host CPU; CEF_TARGET_ARCH=x64 (or arm64) cross-compiles. automate-git
# and make_distrib take --arm64-build / --x64-build, and CEF's gn_args.py only writes
# out/Release_GN_<cpu> for the other CPU when CEF_ENABLE_AMD64 / CEF_ENABLE_ARM64 is set.
# For a second CPU on a checkout that is already built, scripts/rebuild-cef.sh is faster.
CEF_TARGET_ARCH="${CEF_TARGET_ARCH:-$([ "$(uname -m)" = arm64 ] && echo arm64 || echo x64)}"
case "$CEF_TARGET_ARCH" in
  arm64) export CEF_ENABLE_ARM64=1 ;;
  x64)   export CEF_ENABLE_AMD64=1 ;;
  *) echo "CEF_TARGET_ARCH must be arm64 or x64, not $CEF_TARGET_ARCH" >&2; exit 1 ;;
esac
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
    --chromium-checkout="refs/tags/${CEF_VERSION##*chromium-}" \
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
# 0. A CEF update on the same branch (Chromium 156.0.8078.80 → .88): automate-git with
#    --no-chromium-history never moves an existing checkout, and gclient sync skips
#    src as an unmanaged solution, so move it here. Reverting src and the repos CEF
#    patches drops CEF's and Cra's patches; steps 2 and 3 put them back.
#    The same goes for src/cef: automate-git copies the CEF checkout there only in the
#    run that moves the CEF commit, so a run that stopped right after that left src/cef
#    on the old commit with the last round's Cra edits, and every later run built it.
CHROMIUM_VERSION="${CEF_VERSION##*chromium-}"
revert_patched() {
  for repo in . $(sed -nE "s/.*'path': '([^']+)'.*/\1/p" chromium/src/cef/patch/patch.cfg | sort -u); do
    [ -d "chromium/src/$repo" ] && git -C "chromium/src/$repo" checkout -- .
  done
}
if [ -d chromium/src/cef/.git ] && [[ "$(git -C chromium/src/cef rev-parse HEAD)" != "$CEF_COMMIT"* ]]; then
  echo "Moving chromium/src/cef to CEF $CEF_COMMIT"
  revert_patched
  git -C chromium/src/cef checkout -- .
  git -C chromium/src/cef fetch origin "$CEF_BRANCH"
  git -C chromium/src/cef checkout "$CEF_COMMIT"
fi
if [ -f chromium/src/chrome/VERSION ] &&
   [ "$(cut -d= -f2 chromium/src/chrome/VERSION | paste -sd. -)" != "$CHROMIUM_VERSION" ]; then
  echo "Moving the Chromium checkout to $CHROMIUM_VERSION"
  revert_patched
  sed -i '' -E "s#(src\.git@)[0-9.]+#\1$CHROMIUM_VERSION#" chromium/.gclient
  git -C chromium/src fetch --depth 1 origin "refs/tags/$CHROMIUM_VERSION:refs/tags/$CHROMIUM_VERSION"
  git -C chromium/src checkout "$CHROMIUM_VERSION"
  (cd chromium && gclient sync --nohooks --no-history && gclient runhooks)
fi
# 1. Check out Chromium + CEF.
automate --no-build --no-distrib
# 2. CEF's hook: applies CEF's own patches (patcher.py) and writes the GN projects
#    from GN_DEFINES. It has to run before Cra's patches, not after them:
#    gcm-enabled.patch reverses CEF's components_gcm_disable.patch, and every
#    patcher run re-applies that one. automate --force-build runs this hook right
#    before ninja, which is why the build below calls autoninja itself.
(cd chromium/src/cef && python3 tools/gclient_hook.py)
# 3. Cra's Chromium fixes on top (skipped when already applied).
for p in "$PATCHES"/*.patch; do
  if git -C chromium/src apply --check "$p" 2>/dev/null; then
    git -C chromium/src apply "$p" && echo "Applied $(basename "$p")"
  else
    git -C chromium/src apply --check --reverse "$p" || { echo "$(basename "$p") does not apply" >&2; exit 1; }
  fi
done
# 4. Build. make_distrib takes the framework from cefclient.app.
(cd chromium/src && autoninja -C "out/Release_GN_$CEF_TARGET_ARCH" cefclient)
LC_ALL=C grep -c -a GCM.RegistrationCacheStatus \
  "chromium/src/out/Release_GN_$CEF_TARGET_ARCH/cefclient.app/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework" >/dev/null \
  || { echo "GCM is stubbed out (components_gcm_disable.patch won over gcm-enabled.patch)" >&2; exit 1; }
# 5. Package. automate-git does not pass --no-symbols on for branches after 7151,
#    and without dSYMs (enable_dsyms=false) make_distrib then fails.
# Only this CPU's package: the other CPU's may not be published yet.
rm -rf chromium/src/cef/binary_distrib/cef_binary_"${CEF_VERSION}"_macos"$([ "$CEF_TARGET_ARCH" = x64 ] && echo x64 || echo arm64)"_minimal*
(cd chromium/src/cef/tools && python3 make_distrib.py --output-dir=../binary_distrib --allow-partial \
  --ninja-build "$ARCH_FLAG" --minimal --no-docs --no-symbols)
