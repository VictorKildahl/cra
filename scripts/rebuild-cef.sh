#!/bin/bash
# Rebuilds Cra's CEF from the checkout scripts/build-cef.sh left, for one or both CPUs.
#   scripts/rebuild-cef.sh            arm64 and x64
#   scripts/rebuild-cef.sh x64        one CPU
# Then publish each: scripts/publish-cef.sh (arm64), CEF_ARCH=macosx64 scripts/publish-cef.sh.
#
# For a patch round (a new or changed file in scripts/cef-patches) and for adding the
# second CPU (update-cef.sh runs it for x64). It skips automate-git and CEF's gclient
# hook: every patcher run puts components_gcm_disable.patch back over gcm-enabled.patch
# and compiles Web Push out. A new CEF version goes through scripts/update-cef.sh.
#
# Both CPUs share the ~42 GB of sources; each has its own out/Release_GN_<cpu> (~12 GB).
# The first x64 build compiles everything (hours); later rounds take minutes per CPU.
set -euo pipefail
cd "$(dirname "$0")/.."

CEF_BUILD_DIR="${CEF_BUILD_DIR:-$HOME/cef-build.noindex}"
SRC="$CEF_BUILD_DIR/chromium/src"
PATCHES="$PWD/scripts/cef-patches"
CPUS=("$@")
[ ${#CPUS[@]} -gt 0 ] || CPUS=(arm64 x64)
for cpu in "${CPUS[@]}"; do
  [[ "$cpu" =~ ^(arm64|x64)$ ]] || { echo "usage: scripts/rebuild-cef.sh [arm64] [x64]" >&2; exit 1; }
done

eval "$(grep -E '^CEF_VERSION=' scripts/fetch-cef.sh)"
eval "$(grep -E '^export GN_DEFINES=' scripts/build-cef.sh)"
CEF_COMMIT="$(sed -E 's/.*\+g([0-9a-f]+)\+.*/\1/' <<<"$CEF_VERSION")"
CHROMIUM="${CEF_VERSION##*chromium-}"

# The checkout must be the pinned version, built once by build-cef.sh.
[ -d "$SRC/cef" ] || { echo "No CEF checkout in $CEF_BUILD_DIR; run scripts/build-cef.sh" >&2; exit 1; }
HAVE_CHROMIUM="$(. "$SRC/chrome/VERSION" && echo "$MAJOR.$MINOR.$BUILD.$PATCH")"
HAVE_CEF="$(git -C "$SRC/cef" rev-parse HEAD)"
if [ "$HAVE_CHROMIUM" != "$CHROMIUM" ] || [[ "$HAVE_CEF" != "$CEF_COMMIT"* ]]; then
  echo "The checkout is Chromium $HAVE_CHROMIUM, CEF ${HAVE_CEF:0:7}; fetch-cef.sh pins $CEF_VERSION." >&2
  echo "Move it with scripts/update-cef.sh." >&2
  exit 1
fi
# One build at a time: both CPUs share the sources and every core.
if pgrep -fq 'siso ninja|autoninja'; then
  echo "Another Chromium build is running; wait for it." >&2
  exit 1
fi

export PATH="$CEF_BUILD_DIR/depot_tools:$PATH"  # make_distrib needs its clang-format
export DEPOT_TOOLS_UPDATE=0
export CEF_ARCHIVE_FORMAT=tar.bz2

# Cra's patches: new ones go on, applied ones stay. A changed patch applies neither way:
# reverse its old version by hand (git -C chromium/src apply -R) and run again.
for p in "$PATCHES"/*.patch; do
  if git -C "$SRC" apply --check --reverse "$p" 2>/dev/null; then
    continue
  elif git -C "$SRC" apply --check "$p" 2>/dev/null; then
    git -C "$SRC" apply "$p" && echo "Applied $(basename "$p")"
  else
    echo "$(basename "$p") does not apply; reverse its old version first" >&2
    exit 1
  fi
done

for cpu in "${CPUS[@]}"; do
  OUT="out/Release_GN_$cpu"
  if [ ! -f "$SRC/$OUT/build.ninja" ]; then
    FREE_GB=$(( $(df -k "$CEF_BUILD_DIR" | awk 'NR==2 {print $4}') / 1024 / 1024 ))
    [ "$FREE_GB" -ge 25 ] || { echo "A first $cpu build needs ~15 GB plus packaging; $FREE_GB GB free" >&2; exit 1; }
    # The args.gn CEF's gclient_hook.py would write for this CPU (it differs from the
    # other CPU's only in target_cpu), without running the hook's patcher.
    echo "Configuring $OUT"
    mkdir -p "$SRC/$OUT"
    (cd "$SRC/cef/tools" && CEF_ENABLE_ARM64=1 CEF_ENABLE_AMD64=1 python3 -c "
import sys, gn_args
print(gn_args.GetConfigFileContents(gn_args.GetAllPlatformConfigs({}, quiet=True)[sys.argv[1]]), end='')
" "Release_GN_$cpu") > "$SRC/$OUT/args.gn"
    (cd "$SRC" && gn gen "$OUT")
  fi

  echo "Building CEF $CEF_VERSION for $cpu"
  START=$SECONDS
  # make_distrib copies the framework out of cefclient.app.
  (cd "$SRC" && autoninja -C "$OUT" cefsimple cefclient)

  PLATFORM="$([ "$cpu" = x64 ] && echo macosx64 || echo macosarm64)"
  NAME="cef_binary_${CEF_VERSION}_${PLATFORM}_minimal"
  rm -rf "$SRC/cef/binary_distrib/$NAME" "$SRC/cef/binary_distrib/$NAME".*
  # automate-git does not pass --no-symbols on for branches after 7151, and without
  # dSYMs (enable_dsyms=false) make_distrib then fails.
  (cd "$SRC/cef/tools" && python3 make_distrib.py --output-dir=../binary_distrib --allow-partial \
    --ninja-build "--$cpu-build" --minimal --no-docs --no-symbols)

  ARCHIVE="$SRC/cef/binary_distrib/$NAME.tar.bz2"
  FRAMEWORK="$SRC/cef/binary_distrib/$NAME/Release/Chromium Embedded Framework.framework/Chromium Embedded Framework"
  [ -f "$ARCHIVE" ] || { echo "make_distrib wrote no $ARCHIVE" >&2; exit 1; }
  WANT_ARCH="$([ "$cpu" = x64 ] && echo x86_64 || echo arm64)"
  [ "$(lipo -archs "$FRAMEWORK")" = "$WANT_ARCH" ] || { echo "Framework is $(lipo -archs "$FRAMEWORK"), not $WANT_ARCH" >&2; exit 1; }
  LC_ALL=C grep -qa "Cra Safe Storage" "$FRAMEWORK" || { echo "Framework names no Cra Safe Storage" >&2; exit 1; }
  LC_ALL=C grep -qa "GCM.RegistrationCacheStatus" "$FRAMEWORK" || { echo "GCM is compiled out (Web Push)" >&2; exit 1; }
  # Both CPUs come from the same patched sources, so the Cra.* page methods the patches
  # add must match the other CPU's package when there is one. Only NUL-terminated
  # strings count: a literal of 8 bytes or less, like Cra.load, compiles to an immediate,
  # which arm64 splits up but x86_64's movabs keeps whole ("Cra.loadH" in a plain grep).
  OTHER="$([ "$cpu" = x64 ] && echo macosarm64 || echo macosx64)"
  OTHER_FW="$SRC/cef/binary_distrib/cef_binary_${CEF_VERSION}_${OTHER}_minimal/Release/Chromium Embedded Framework.framework/Chromium Embedded Framework"
  if [ -f "$OTHER_FW" ]; then
    markers() { perl -0777 -ne 'my %s; $s{$1} = 1 while /(Cra\.[A-Za-z]{2,})\0/g; print join(" ", sort keys %s)' "$1"; }
    MINE="$(markers "$FRAMEWORK")" THEIRS="$(markers "$OTHER_FW")"
    if [ "$MINE" != "$THEIRS" ]; then
      echo "Cra.* methods differ from $OTHER's package:" >&2
      echo "  $PLATFORM: $MINE" >&2
      echo "  $OTHER: $THEIRS" >&2
      exit 1
    fi
    echo "Same Cra.* methods as $OTHER: $MINE"
  fi
  echo "CEF for $cpu in $(( (SECONDS - START) / 60 )) min: $ARCHIVE"
done
