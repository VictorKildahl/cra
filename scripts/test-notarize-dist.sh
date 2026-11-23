#!/bin/bash
# scripts/notarize-dist.sh with stand-ins for Apple (GitHub #720): a new build is notarized in the DMG, the app gets
# its ticket, the DMG is packed again with that app and notarized in turn; a rerun that stopped on the second
# submission only waits for it, and one that stopped on the first goes through both.
set -euo pipefail
cd "$(dirname "$0")/.."
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
LOG="$T/calls"
# notarize <dmg> [app]: logs, and staples the app (a marker) when given one.
cat > "$T/notarize" <<'STUB'
#!/bin/bash
echo "notarize $(basename "$1")${2:+ + $(basename "$2")}" >> "$LOG"
[ -n "${2:-}" ] && touch "$2/stapled"
exit 0
STUB
# package <app>: logs whether the app it packs is stapled.
cat > "$T/package" <<'STUB'
#!/bin/bash
echo "package $(basename "$1") $([ -e "$1/stapled" ] && echo stapled || echo unstapled)" >> "$LOG"
STUB
# stapler validate -q <app>
cat > "$T/stapler" <<'STUB'
#!/bin/bash
[ -e "$3/stapled" ]
STUB
chmod +x "$T/notarize" "$T/package" "$T/stapler"
export LOG CRA_NOTARIZE="$T/notarize" CRA_PACKAGE="$T/package" CRA_STAPLER="$T/stapler"
fail() { echo "notarize-dist: $*" >&2; exit 1; }
run() { : > "$LOG"; scripts/notarize-dist.sh "$T/Cra.app" "$T/Cra.dmg" > /dev/null; cat "$LOG"; }

# A new build.
mkdir -p "$T/Cra.app"
echo pending > "$T/Cra.dmg.submission"
got="$(run)"
want="$(printf 'notarize Cra.dmg + Cra.app\npackage Cra.app stapled\nnotarize Cra.dmg')"
[ "$got" = "$want" ] || fail "a new build ran: $got"
[ ! -e "$T/Cra.dmg.submission" ] || fail "the submission id was left behind"

# A rerun that stopped on the second submission: the app is stapled, the DMG holds it.
got="$(run)"
[ "$got" = "notarize Cra.dmg" ] || fail "a rerun on the second submission ran: $got"

# A rerun that stopped on the first: the app has no ticket yet.
rm "$T/Cra.app/stapled"
got="$(run)"
[ "$got" = "$want" ] || fail "a rerun on the first submission ran: $got"
echo "Notarize dist: the DMG is packed again with the stapled app and notarized; reruns resume either submission"
