#!/bin/bash
# scripts/promote.sh keeps the latest release's feed download counts in scripts/feed-counts.tsv before it uploads
# over the feeds, which starts GitHub's counts over, and commits them with scripts/stable-version (docs/release.md,
# "Channels"). Runs promote.sh in a git copy of the scripts with a stand-in gh, so nothing reaches GitHub and the
# real repository is never touched.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
DIR="$(mktemp -d /tmp/cra-feed-counts.XXXXXX)"
trap 'rm -rf "$DIR"' EXIT

REPO_COPY="$DIR/repo"
mkdir -p "$REPO_COPY/scripts" "$DIR/bin"
cp scripts/promote.sh scripts/feed-counts.sh scripts/appcast-feeds.py "$REPO_COPY/scripts/"
echo 0.1.40 > "$REPO_COPY/scripts/stable-version"
grep '^#' scripts/feed-counts.tsv > "$REPO_COPY/scripts/feed-counts.tsv"
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
git -C "$REPO_COPY" init -q
git -C "$REPO_COPY" add -A
git -C "$REPO_COPY" commit -q -m "Before promoting"
# Someone else's work in the same checkout, staged but not theirs to commit yet.
echo "half done" > "$REPO_COPY/other.txt"
git -C "$REPO_COPY" add other.txt
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
    # The promoted release's web features (scripts/release.sh): WEB_FEATURES=passed (default), failed or none.
    if [ "\$pattern" = web-features-arm64.txt ]; then
      case "\${WEB_FEATURES:-passed}" in
        none) exit 1 ;;
        *) printf 'passed 61, skipped 0, failed 0\nresult: %s\n' "\${WEB_FEATURES:-passed}" > "\$dest/\$pattern" ;;
      esac
    elif [ "\$tag" = v0.1.46 ]; then cp "$ROOT/Tests/Fixtures/Appcast/newest.xml" "\$dest/\$pattern"
    else cp "$ROOT/Tests/Fixtures/Appcast/stable.xml" "\$dest/\$pattern"; fi ;;
  "release upload")
    echo "kept before upload: \$(grep -vc '^#' "$REPO_COPY/scripts/feed-counts.tsv")" >> "$LOG" ;;
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
counts() { grep -v '^#' "$REPO_COPY/scripts/feed-counts.tsv" | cut -f2- | tr '\t\n' ' |'; }
commits() { git -C "$REPO_COPY" rev-list --count HEAD; }
EXPECTED='v0.1.46 appcast-intel.xml 35|v0.1.46 appcast-stable-intel.xml 0|v0.1.46 appcast-stable.xml 31|v0.1.46 appcast.xml 1243|'

check "feed-counts.sh lists the feeds' counts, not the archives'" \
  "$("$REPO_COPY/scripts/feed-counts.sh" v0.1.46 | cut -f2- | tr '\t\n' ' |')" "$EXPECTED"
check "feed-counts.sh stamps each line with the UTC time" \
  "$("$REPO_COPY/scripts/feed-counts.sh" v0.1.46 | cut -f1 | grep -cE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$')" 4

: > "$LOG"
"$REPO_COPY/scripts/promote.sh" 0.1.43 --dry-run > "$DIR/dry.out"
check "a dry run shows the counts" "$(grep -c $'\tv0.1.46\tappcast' "$DIR/dry.out")" 4
check "a dry run keeps nothing" "$(counts)" ""
check "a dry run commits nothing" "$(commits)" 1
check "a dry run uploads nothing" "$(grep -c '^release upload' "$LOG" || true)" 0

: > "$LOG"
"$REPO_COPY/scripts/promote.sh" 0.1.43 > /dev/null
check "promoting keeps the counts" "$(counts)" "$EXPECTED"
check "the counts are kept before the upload starts them over" "$(grep '^kept before upload' "$LOG")" \
  "kept before upload: 4"
check "promoting still uploads the feeds" "$(grep -c '^release upload -R VictorKildahl/cra v0.1.46 --clobber' "$LOG")" 1
check "promoting still sets stable-version" "$(cat "$REPO_COPY/scripts/stable-version")" 0.1.43
check "promoting commits" "$(git -C "$REPO_COPY" log -1 --format=%s)" "Stable is Cra 0.1.43"
check "the commit holds stable-version and the counts, nothing else" \
  "$(git -C "$REPO_COPY" show --name-only --format= HEAD | tr '\n' ' ')" "scripts/feed-counts.tsv scripts/stable-version "
check "other work in the checkout stays staged and uncommitted" "$(git -C "$REPO_COPY" diff --cached --name-only)" other.txt

"$REPO_COPY/scripts/promote.sh" 0.1.43 > /dev/null
check "a second promotion adds to the earlier counts" "$(counts)" "$EXPECTED$EXPECTED"
check "and commits them too" "$(commits)" 3

# Stable takes only a release whose web features passed (docs/web-features.md).
: > "$LOG"
WEB_FEATURES=failed "$REPO_COPY/scripts/promote.sh" 0.1.43 > /dev/null 2>&1 && refused=no || refused=yes
check "a release that failed its web features isn't promoted" "$refused" yes
check "nor is anything uploaded for it" "$(grep -c '^release upload' "$LOG" || true)" 0
WEB_FEATURES=none "$REPO_COPY/scripts/promote.sh" 0.1.43 > /dev/null 2>&1 && refused=no || refused=yes
check "a release whose web features never ran isn't promoted" "$refused" yes
check "and no commit is made" "$(commits)" 3
WEB_FEATURES=none CRA_PROMOTE_UNTESTED="from before the check" "$REPO_COPY/scripts/promote.sh" 0.1.43 > /dev/null
check "CRA_PROMOTE_UNTESTED promotes it anyway" "$(commits)" 4
exit $FAILED
