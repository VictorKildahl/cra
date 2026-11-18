#!/bin/bash
# scripts/promote.sh keeps the latest release's feed download counts in scripts/feed-counts.tsv before it uploads
# over the feeds, which starts GitHub's counts over (docs/release.md, "Channels"). Runs promote.sh in a copy of the
# scripts with a stand-in gh, so nothing reaches GitHub and the real stable-version and feed-counts.tsv stay as
# they are.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
DIR="$(mktemp -d /tmp/cra-feed-counts.XXXXXX)"
trap 'rm -rf "$DIR"' EXIT

REPO_COPY="$DIR/repo"
mkdir -p "$REPO_COPY/scripts" "$DIR/bin"
cp scripts/promote.sh scripts/feed-counts.sh scripts/appcast-feeds.py "$REPO_COPY/scripts/"
echo 0.1.43 > "$REPO_COPY/scripts/stable-version"
LOG="$DIR/gh.log"

# The stand-in gh: v0.1.46 is the latest release, v0.1.43 the one promoted; feeds come from Tests/Fixtures/Appcast.
cat > "$DIR/bin/gh" <<GH
#!/bin/bash
echo "\$*" >> "$LOG"
case "\$1 \$2" in
  "release view")  # view -R <repo> --json tagName -q .tagName (the latest) or view -R <repo> <tag> --json tagName
    if [ "\$5" = "--json" ]; then echo v0.1.46; fi ;;
  "release download")  # download -R <repo> <tag> -p <pattern> -D <dir> --clobber
    tag="\$5"; pattern="\$7"; dest="\$9"
    if [ "\$tag" = v0.1.46 ]; then cp "$ROOT/Tests/Fixtures/Appcast/newest.xml" "\$dest/\$pattern"
    else cp "$ROOT/Tests/Fixtures/Appcast/stable.xml" "\$dest/\$pattern"; fi ;;
  "release upload")
    echo "kept before upload: \$(cat "$REPO_COPY/scripts/feed-counts.tsv" 2>/dev/null | wc -l | tr -d ' ')" >> "$LOG" ;;
  "api repos/VictorKildahl/cra/releases/tags/v0.1.46")
    cat <<'JSON'
{"assets": [
  {"name": "appcast.xml", "download_count": 1243},
  {"name": "Cra.zip", "download_count": 466},
  {"name": "appcast-stable.xml", "download_count": 31},
  {"name": "appcast-intel.xml", "download_count": 35},
  {"name": "appcast-stable-intel.xml", "download_count": 0},
  {"name": "Cra.dmg", "download_count": 161}
]}
JSON
    ;;
  *) echo "unexpected gh \$*" >&2; exit 1 ;;
esac
GH
chmod +x "$DIR/bin/gh"
export PATH="$DIR/bin:$PATH"

FAILED=0
check() {
  if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAILED: $1: expected '$3', got '$2'"; FAILED=1; fi
}
counts() { cut -f2- "$REPO_COPY/scripts/feed-counts.tsv" 2>/dev/null | tr '\t\n' ' |'; }
EXPECTED='v0.1.46 appcast-intel.xml 35|v0.1.46 appcast-stable-intel.xml 0|v0.1.46 appcast-stable.xml 31|v0.1.46 appcast.xml 1243|'

check "feed-counts.sh lists the feeds' counts, not the archives'" \
  "$("$REPO_COPY/scripts/feed-counts.sh" v0.1.46 | cut -f2- | tr '\t\n' ' |')" "$EXPECTED"
check "feed-counts.sh stamps each line with the UTC time" \
  "$("$REPO_COPY/scripts/feed-counts.sh" v0.1.46 | cut -f1 | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$')" 4

: > "$LOG"
"$REPO_COPY/scripts/promote.sh" 0.1.43 --dry-run > "$DIR/dry.out"
check "a dry run shows the counts" "$(grep -c $'\tv0.1.46\tappcast' "$DIR/dry.out")" 4
check "a dry run keeps nothing" "$([ -e "$REPO_COPY/scripts/feed-counts.tsv" ] && echo kept || echo none)" none
check "a dry run uploads nothing" "$(grep -c '^release upload' "$LOG" || true)" 0

: > "$LOG"
"$REPO_COPY/scripts/promote.sh" 0.1.43 > /dev/null
check "promoting keeps the counts" "$(counts)" "$EXPECTED"
check "the counts are kept before the upload starts them over" "$(grep '^kept before upload' "$LOG")" \
  "kept before upload: 4"
check "promoting still uploads the feeds" "$(grep -c '^release upload -R VictorKildahl/cra v0.1.46 --clobber' "$LOG")" 1
check "promoting still sets stable-version" "$(cat "$REPO_COPY/scripts/stable-version")" 0.1.43

"$REPO_COPY/scripts/promote.sh" 0.1.43 > /dev/null
check "a second promotion adds to the earlier counts" "$(counts)" "$EXPECTED$EXPECTED"
exit $FAILED
