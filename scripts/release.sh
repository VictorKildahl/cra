#!/bin/bash
# Full distributable build: build, sign, notarize, package, notarize the DMG, and
# write the Sparkle appcast for the update archive, once per CPU.
#   CRA_VERSION=0.1.0 CRA_SIGN_IDENTITY="Developer ID Application: …" scripts/release.sh
# Every release ships Apple silicon (Cra.dmg, Cra.zip, appcast.xml, appcast-stable.xml) and Intel
# (Cra-Intel.dmg, Cra-Intel.zip, appcast-intel.xml, appcast-stable-intel.xml). CRA_ARCHS="arm64" (or "x86_64")
# builds one; the Release workflow runs one per job and merges them.
# Without CRA_SIGN_IDENTITY it still produces an ad-hoc build and packages, so
# the pipeline can be exercised before certificates exist. The appcast needs the
# update signing key (SPARKLE_PRIVATE_KEY, or the "cra" key in the login keychain).
set -euo pipefail
cd "$(dirname "$0")/.."
export CRA_VERSION="${CRA_VERSION:-0.1.0}"
# One build number for both CPUs.
export CRA_BUILD="${CRA_BUILD:-$(date +%Y%m%d%H%M)}"
# Release builds carry the update feed (scripts/build.sh drops it otherwise).
export CRA_RELEASE=1
IDENTITY="${CRA_SIGN_IDENTITY:--}"
ARCHS="${CRA_ARCHS:-arm64 x86_64}"

# A release ships an engine with every security fix Chrome stable has shipped: Chromium fixes security bugs only in
# its newest builds. CRA_ALLOW_OLD_ENGINE=1 ships the pinned one anyway (an urgent fix while the new engine
# is still building); say so in the release notes. CRA_ENGINE=cef releases on CEF, with CEF's check.
if [ "${CRA_ENGINE:-chromium}" = cef ]; then
  if [ "${CRA_ALLOW_OLD_CEF:-}" != 1 ]; then
    scripts/check-cef-update.sh --check ||
      { echo "Release stopped: CEF is behind (CRA_ALLOW_OLD_CEF=1 to ship it anyway)" >&2; exit 1; }
  fi
elif [ "${CRA_ALLOW_OLD_ENGINE:-}" != 1 ]; then
  scripts/check-engine-update.sh --check ||
    { echo "Release stopped: the engine lacks Chrome stable's security fixes (CRA_ALLOW_OLD_ENGINE=1 to ship it anyway)" >&2; exit 1; }
fi

# The Stable channel's release (GitHub #476, docs/release.md "Channels"): scripts/promote.sh sets it. Its own
# appcast holds its signed item, which goes into this release's feeds next to the new one.
export CRA_STABLE_VERSION="${CRA_STABLE_VERSION:-$(tr -d '[:space:]' < scripts/stable-version)}"
STABLE_DIR="$(mktemp -d /tmp/cra-stable.XXXXXX)"
trap 'rm -rf "$STABLE_DIR"' EXIT

# CRA_RESUME=<dir> (the Release workflow's rerun, or by hand): a CPU whose signed app, DMG and
# Apple submission id are in <dir> (scripts/keep-pending.sh wrote them when a run stopped while
# Apple was still checking) is not built again: its notarization is picked up where it was.
RESUME="${CRA_RESUME:-}"
[ -n "$RESUME" ] || rm -rf build/dist
mkdir -p build/dist
for ARCH in $ARCHS; do
  # build.sh's rule: the host CPU builds build/Cra.app, the other one build/<arch>/Cra.app.
  if [ "$ARCH" = "$(uname -m)" ]; then APP="build/Cra.app"; else APP="build/$ARCH/Cra.app"; fi
  if [ -n "$RESUME" ] && [ -f "$RESUME/$ARCH/Cra.app.zip" ] && ls "$RESUME/$ARCH"/*.dmg.submission >/dev/null 2>&1; then
    echo "Resuming $ARCH from $RESUME/$ARCH (submission $(cat "$RESUME/$ARCH"/*.dmg.submission))"
    rm -rf "$APP" && mkdir -p "$(dirname "$APP")"
    ditto -x -k "$RESUME/$ARCH/Cra.app.zip" "$(dirname "$APP")"
    cp "$RESUME/$ARCH"/*.dmg "$RESUME/$ARCH"/*.dmg.submission build/dist/
    scripts/fetch-sparkle.sh   # build.sh fetches it; the appcast below signs with it
    SUFFIX="$(scripts/asset-suffix.sh "$APP")"
  else
    CRA_ARCH="$ARCH" scripts/build.sh release
    SUFFIX="$(scripts/asset-suffix.sh "$APP")"
    rm -f "build/dist/Cra$SUFFIX.dmg.submission"
    # The DMG holds the app as signed; its notarization covers both, and notarize-dist.sh packs it again stapled.
    scripts/package.sh "$APP"
  fi

  # The web features (docs/web-features.md): file pickers, print, dialogs, prompts and choosers on this build, in
  # the background while Apple notarizes it. 0.1.49 shipped with every upload button dead (#571) and print preview
  # 3 pt tall (#574) because nothing tried them. On a copy (stapling writes into the app), for this Mac's CPU
  # (the other CPU's app is the same code). CRA_SKIP_WEB_FEATURES="<why>" releases without it; say why in the notes.
  # Then the snapshots (scripts/scenario.sh snapshots): every scenario's snapshots against Tests/Snapshots on a 2x
  # screen, one at a time, on the same copy. Two broke on main unseen when a PR gave a fixture its icons (22 Nov
  # 2026): nothing ran them. CRA_SKIP_SNAPSHOTS="<why>" releases without them.
  WEB_FEATURES_PID=""
  if [ "$ARCH" = "$(uname -m)" ] && { [ -z "${CRA_SKIP_WEB_FEATURES:-}" ] || [ -z "${CRA_SKIP_SNAPSHOTS:-}" ]; }; then
    rm -rf build/web-features && mkdir -p build/web-features
    ditto "$APP" build/web-features/Cra.app
    (
      # Each writes 0 or 1 (set -e would end the subshell on the first failure, before the snapshots ran).
      if [ -z "${CRA_SKIP_WEB_FEATURES:-}" ]; then
        if CRA_APP="$PWD/build/web-features/Cra.app" CRA_BUDGETS=report scripts/scenario.sh web-features \
          > build/web-features/run.log 2>&1; then echo 0; else echo 1; fi > build/web-features/web-features.status
      fi
      if [ -z "${CRA_SKIP_SNAPSHOTS:-}" ]; then
        if CRA_APP="$PWD/build/web-features/Cra.app" scripts/scenario.sh snapshots \
          > build/web-features/snapshots.log 2>&1; then echo 0; else echo 1; fi > build/web-features/snapshots.status
      fi
    ) &
    WEB_FEATURES_PID=$!
  fi
  [ -z "${CRA_SKIP_WEB_FEATURES:-}" ] || echo "web features skipped: $CRA_SKIP_WEB_FEATURES" | tee "build/dist/web-features-$ARCH.txt"
  [ -z "${CRA_SKIP_SNAPSHOTS:-}" ] || echo "snapshots skipped: $CRA_SKIP_SNAPSHOTS" | tee "build/dist/snapshots-$ARCH.txt"

  if [ "$IDENTITY" != "-" ]; then
    # Two submissions per CPU (notarize-dist.sh): the DMG as packaged, whose ticket goes on the app, then the DMG
    # packed again with that stapled app. An install from the DMG then carries its ticket offline (GitHub #720).
    scripts/notarize-dist.sh "$APP" "build/dist/Cra$SUFFIX.dmg"
    # The DMG and the app inside it both carry their tickets, or the release stops.
    MNT="$(mktemp -d)"
    hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "build/dist/Cra$SUFFIX.dmg" > /dev/null
    if xcrun stapler validate -q "$MNT/Cra.app"; then IN_DMG=stapled; else IN_DMG=missing; fi
    hdiutil detach -quiet "$MNT" || true
    [ "$IN_DMG" = stapled ] || { echo "Release stopped: Cra.app in Cra$SUFFIX.dmg has no notarization ticket" >&2; exit 1; }
    xcrun stapler validate -q "build/dist/Cra$SUFFIX.dmg" ||
      { echo "Release stopped: Cra$SUFFIX.dmg has no notarization ticket" >&2; exit 1; }
    # Zip the stapled app: Sparkle updates and scripts/install.sh carry the ticket offline.
    ditto -c -k --keepParent "$APP" "build/dist/Cra$SUFFIX.zip"
    # On its own line so set -e fails the release when Gatekeeper rejects the app.
    spctl --assess --type execute --verbose=2 "$APP"
    echo "Gatekeeper accepts $APP"
  else
    echo "Ad-hoc build: not notarized. Set CRA_SIGN_IDENTITY and notary credentials for a distributable build." >&2
  fi
  if [ -n "$WEB_FEATURES_PID" ]; then
    echo "Waiting for the web features and snapshots on $ARCH (build/web-features/run.log, snapshots.log)"
    wait "$WEB_FEATURES_PID" || true
    # Never left registered next to the installed Cra.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
      -u build/web-features/Cra.app 2>/dev/null || true
    rm -rf build/web-features/Cra.app
    if [ -z "${CRA_SKIP_WEB_FEATURES:-}" ]; then
      cp build/scenarios/web-features.txt "build/dist/web-features-$ARCH.txt"
      cat "build/dist/web-features-$ARCH.txt"
      if [ "$(cat build/web-features/web-features.status 2>/dev/null)" != 0 ]; then
        tail -40 build/web-features/run.log >&2
        echo "Release stopped: a web feature is broken on this build (docs/web-features.md)." >&2
        echo "Fix it, or CRA_SKIP_WEB_FEATURES=\"<why>\" to release anyway and say so in the notes." >&2
        exit 1
      fi
    fi
    if [ -z "${CRA_SKIP_SNAPSHOTS:-}" ]; then
      cp build/scenarios/snapshots.txt "build/dist/snapshots-$ARCH.txt" 2>/dev/null || true
      cat build/web-features/snapshots.log
      if [ "$(cat build/web-features/snapshots.status 2>/dev/null)" != 0 ]; then
        echo "Release stopped: a snapshot differs from Tests/Snapshots on this build (build/scenarios/<name>/snapshots/*.diff.png)." >&2
        echo "Fix it, re-record an intended change (CRA_SNAPSHOT_RECORD=1 scripts/scenario.sh <name>, on a Retina screen)," >&2
        echo "or CRA_SKIP_SNAPSHOTS=\"<why>\" to release anyway and say so in the notes." >&2
        exit 1
      fi
    fi
  fi
  SUFFIX_LOWER="$(echo "$SUFFIX" | tr '[:upper:]' '[:lower:]')"
  export CRA_STABLE_FEED="$STABLE_DIR/appcast$SUFFIX_LOWER.xml"
  if [ "$CRA_STABLE_VERSION" != "$CRA_VERSION" ]; then
    curl -fsSL -o "$CRA_STABLE_FEED" \
      "https://github.com/VictorKildahl/cra/releases/download/v$CRA_STABLE_VERSION/appcast$SUFFIX_LOWER.xml"
  else
    unset CRA_STABLE_FEED  # this release is Stable itself
  fi
  # Installed copies update from the zip; the appcast must sign the final one.
  scripts/appcast.sh "build/dist/Cra$SUFFIX.zip" "$APP" "${CRA_RELEASE_NOTES:-}"
done
(cd build/dist && shasum -a 256 Cra*.zip Cra*.dmg > SHA256SUMS.txt)
echo "Release artifacts in build/dist:"
ls -la build/dist
