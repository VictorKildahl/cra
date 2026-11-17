#!/bin/bash
# Submits a file to Apple's notary service, waits, and staples the ticket.
#   scripts/notarize.sh <file.zip|file.dmg> [path/to/Cra.app to staple]
# Credentials, the first that is set:
#   NOTARY_KEYCHAIN_PROFILE   a profile stored with `xcrun notarytool store-credentials`
#   NOTARY_API_KEY_PATH, NOTARY_API_KEY_ID, NOTARY_API_ISSUER
#                             an App Store Connect API key (.p8) with the Developer role: it
#                             doesn't expire with an app-specific password or an Apple ID lock
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD   (an app-specific password)
#
# The submission id goes next to the file (<file>.submission) as soon as Apple has it. When that
# file is already there, nothing is uploaded again: the script waits for that submission. So a
# release that stopped while Apple was still checking (a wait that timed out, a cancelled job)
# picks the same submission up instead of building and submitting again (Cra 0.1.47, 17 Nov 2026:
# Apple took 52 minutes, and the 30-minute wait threw away the build Apple then accepted).
set -euo pipefail
FILE="$1"
STAPLE_APP="${2:-}"
SUBMISSION="$FILE.submission"
if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  AUTH=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [ -n "${NOTARY_API_KEY_PATH:-}" ] && [ -n "${NOTARY_API_KEY_ID:-}" ] && [ -n "${NOTARY_API_ISSUER:-}" ]; then
  AUTH=(--key "$NOTARY_API_KEY_PATH" --key-id "$NOTARY_API_KEY_ID" --issuer "$NOTARY_API_ISSUER")
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
  AUTH=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
else
  # Only called for Developer ID builds, and Gatekeeper rejects those unnotarized.
  echo "No notarization credentials in the environment. Set NOTARY_KEYCHAIN_PROFILE, NOTARY_API_KEY_PATH/_ID/ISSUER, or APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD." >&2
  exit 1
fi
# The stapler fetches the ticket from Apple's CloudKit, and from GitHub's runners that
# connection often drops (NSURLErrorDomain -1005, exit 68) after notarization succeeded.
staple() {
  local attempt
  for attempt in 1 2 3 4 5; do
    xcrun stapler staple "$1" && return 0
    echo "Stapling $(basename "$1") failed (attempt $attempt), retrying…" >&2
    sleep $((attempt * 10))
  done
  return 1
}
json() { /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin).get('$1', ''))"; }

if [ -s "$SUBMISSION" ]; then
  ID="$(tr -d '[:space:]' < "$SUBMISSION")"
  echo "Waiting for $(basename "$FILE")'s earlier submission ${ID}…"
else
  echo "Notarizing $(basename "$FILE")…"
  ID="$(xcrun notarytool submit "$FILE" "${AUTH[@]}" --output-format json | json id)"
  [ -n "$ID" ] || { echo "Apple returned no submission id for $FILE" >&2; exit 1; }
  echo "$ID" > "$SUBMISSION"
  echo "Submitted as $ID"
fi
# Two hours: Apple's queue usually answers in minutes but took 52 on 17 Nov 2026. Each job notarizes
# one file, well inside GitHub's 6-hour job limit. A wait that still runs out leaves $SUBMISSION, and
# the next run picks it up.
xcrun notarytool wait "$ID" "${AUTH[@]}" --timeout 2h
STATUS="$(xcrun notarytool info "$ID" "${AUTH[@]}" --output-format json | json status)"
if [ "$STATUS" != "Accepted" ]; then
  echo "Notarization of $(basename "$FILE") ended $STATUS:" >&2
  xcrun notarytool log "$ID" "${AUTH[@]}" >&2 || true
  rm -f "$SUBMISSION"   # a rejected build needs a new one, not another wait
  exit 1
fi
case "$FILE" in
  *.dmg) staple "$FILE" ;;
esac
if [ -n "$STAPLE_APP" ]; then
  staple "$STAPLE_APP"
fi
echo "Notarized."
