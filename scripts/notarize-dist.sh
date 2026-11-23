#!/bin/bash
# Notarizes one CPU's DMG so the app inside it carries its own ticket (GitHub #720). The DMG used to be notarized
# once, with the app packed before Apple had seen it: the ticket went on the DMG and on build/Cra.app, never on the
# copy in the DMG, so an install from the DMG had none and macOS had to ask Apple online on its first launch.
#   1. The DMG as packaged: its notarization covers the app inside, whose ticket goes on the app (notarize.sh).
#   2. package.sh packs the DMG again with that stapled app, and it is notarized and stapled in turn.
# A run that stopped while Apple was checking resumes from either (keep-pending.sh keeps the app, the DMG and the
# submission id): a stapled app means the pending submission is the second DMG's.
#   scripts/notarize-dist.sh <path/to/Cra.app> <build/dist/Cra[-Intel].dmg>
# CRA_NOTARIZE, CRA_PACKAGE and CRA_STAPLER stand in for notarize.sh, package.sh and `xcrun stapler` in
# scripts/test-notarize-dist.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:?usage: notarize-dist.sh <Cra.app> <dmg>}"
DMG="${2:?usage: notarize-dist.sh <Cra.app> <dmg>}"
NOTARIZE="${CRA_NOTARIZE:-scripts/notarize.sh}"
PACKAGE="${CRA_PACKAGE:-scripts/package.sh}"
read -r -a STAPLER <<< "${CRA_STAPLER:-xcrun stapler}"

if "${STAPLER[@]}" validate -q "$APP" >/dev/null 2>&1; then
  echo "$(basename "$APP") is stapled: waiting for the DMG that holds it"
  "$NOTARIZE" "$DMG"
else
  "$NOTARIZE" "$DMG" "$APP"
  rm -f "$DMG.submission"
  "$PACKAGE" "$APP"
  "$NOTARIZE" "$DMG"
fi
rm -f "$DMG.submission"
