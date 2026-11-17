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

# A release ships the newest stable engine: Chromium fixes security bugs only in its newest
# version. CRA_ALLOW_OLD_ENGINE=1 ships the pinned one anyway (an urgent fix while the new engine
# is still building); say so in the release notes. CRA_ENGINE=cef releases on CEF, with CEF's check.
if [ "${CRA_ENGINE:-chromium}" = cef ]; then
  if [ "${CRA_ALLOW_OLD_CEF:-}" != 1 ]; then
    scripts/check-cef-update.sh --check ||
      { echo "Release stopped: CEF is behind (CRA_ALLOW_OLD_CEF=1 to ship it anyway)" >&2; exit 1; }
  fi
elif [ "${CRA_ALLOW_OLD_ENGINE:-}" != 1 ]; then
  scripts/check-engine-update.sh --check ||
    { echo "Release stopped: the engine is behind Chrome stable (CRA_ALLOW_OLD_ENGINE=1 to ship it anyway)" >&2; exit 1; }
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
    # The DMG holds the app as signed; one notarization of the DMG covers both.
    scripts/package.sh "$APP"
  fi

  if [ "$IDENTITY" != "-" ]; then
    # One submission per CPU: the DMG, whose ticket covers the app inside it. Stapled to the DMG
    # and to the app (macOS checks the app inside the DMG online, as for most apps).
    scripts/notarize.sh "build/dist/Cra$SUFFIX.dmg" "$APP"
    rm -f "build/dist/Cra$SUFFIX.dmg.submission"
    # Zip the stapled app: Sparkle updates and scripts/install.sh carry the ticket offline.
    ditto -c -k --keepParent "$APP" "build/dist/Cra$SUFFIX.zip"
    # On its own line so set -e fails the release when Gatekeeper rejects the app.
    spctl --assess --type execute --verbose=2 "$APP"
    echo "Gatekeeper accepts $APP"
  else
    echo "Ad-hoc build: not notarized. Set CRA_SIGN_IDENTITY and notary credentials for a distributable build." >&2
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
