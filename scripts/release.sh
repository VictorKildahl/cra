#!/bin/bash
# Full distributable build: build, sign, notarize, package, notarize the DMG, and
# write the Sparkle appcast for the update archive, once per CPU.
#   CRA_VERSION=0.1.0 CRA_SIGN_IDENTITY="Developer ID Application: …" scripts/release.sh
# Every release ships Apple silicon (Cra.dmg, Cra.zip, appcast.xml) and Intel
# (Cra-Intel.dmg, Cra-Intel.zip, appcast-intel.xml). CRA_ARCHS="arm64" (or "x86_64")
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

rm -rf build/dist
for ARCH in $ARCHS; do
  CRA_ARCH="$ARCH" scripts/build.sh release
  # build.sh's rule: the host CPU builds build/Cra.app, the other one build/<arch>/Cra.app.
  if [ "$ARCH" = "$(uname -m)" ]; then APP="build/Cra.app"; else APP="build/$ARCH/Cra.app"; fi
  SUFFIX="$(scripts/asset-suffix.sh "$APP")"

  if [ "$IDENTITY" != "-" ]; then
    # Notarize the app first (as a zip), staple it, then package the stapled app.
    TMPZIP="$(mktemp -d /tmp/cra-notarize.XXXXXX)/Cra.zip"
    ditto -c -k --keepParent "$APP" "$TMPZIP"
    scripts/notarize.sh "$TMPZIP" "$APP"
    rm -rf "$(dirname "$TMPZIP")"
  fi

  scripts/package.sh "$APP"

  if [ "$IDENTITY" != "-" ]; then
    scripts/notarize.sh "build/dist/Cra$SUFFIX.dmg"
    # Re-zip the stapled app so the zip download carries the ticket too.
    ditto -c -k --keepParent "$APP" "build/dist/Cra$SUFFIX.zip"
    # On its own line so set -e fails the release when Gatekeeper rejects the app.
    spctl --assess --type execute --verbose=2 "$APP"
    echo "Gatekeeper accepts $APP"
  else
    echo "Ad-hoc build: not notarized. Set CRA_SIGN_IDENTITY and notary credentials for a distributable build." >&2
  fi
  # Installed copies update from the zip; the appcast must sign the final one.
  scripts/appcast.sh "build/dist/Cra$SUFFIX.zip" "$APP" "${CRA_RELEASE_NOTES:-}"
done
(cd build/dist && shasum -a 256 Cra*.zip Cra*.dmg > SHA256SUMS.txt)
echo "Release artifacts in build/dist:"
ls -la build/dist
