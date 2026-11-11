#!/usr/bin/env bash
# Claude Code PreToolUse hook (Bash): before a release tag (vX.Y.Z) is pushed, checks that the
# release ships the newest CEF. Blocks (exit 2) when
#   - Spotify's index lists a newer stable CEF than scripts/fetch-cef.sh pins
#     (scripts/check-cef-update.sh --check), or
#   - the pinned CEF_RELEASE lacks the Apple silicon or the Intel archive on GitHub, so the
#     Release workflow's build.sh would fail to download it.
# CRA_ALLOW_OLD_CEF=1 on the push skips the first check (release.sh honours it too). When the
# network can't be reached, it warns and lets the push through: release.sh checks again.
set -euo pipefail

command="$(jq -r '.tool_input.command // empty')"
# Only an actual `git push` of a release tag, as in check-release-media.sh.
grep -qE '(^|[;&|(]|\$\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=("[^"]*"|[^[:space:]]+)[[:space:]]+)*git[[:space:]]+push\b' <<<"$command" || exit 0
grep -qE '\bv[0-9]+\.[0-9]+\.[0-9]+\b' <<<"$command" || exit 0

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
if ! grep -q 'CRA_ALLOW_OLD_CEF=1' <<<"$command"; then
  if ! out="$(scripts/check-cef-update.sh --check 2>&1)"; then
    if grep -q "Could not read" <<<"$out"; then
      echo "warning: couldn't read the CEF index; release.sh checks again" >&2
    else
      echo "$out" >&2
      echo "Release blocked: a newer stable CEF is out. Build it first, or push with CRA_ALLOW_OLD_CEF=1 for an urgent fix." >&2
      exit 2
    fi
  fi
fi

eval "$(grep -E '^(CEF_VERSION|CEF_RELEASE)=' scripts/fetch-cef.sh)"
for arch in macosarm64 macosx64; do
  url="https://github.com/VictorKildahl/cra/releases/download/${CEF_RELEASE}/cef_binary_${arch}_minimal.tar.bz2"
  code="$(curl -s -o /dev/null -w '%{http_code}' -I -L --max-time 15 "$url" || true)"
  if [ "$code" = 404 ]; then
    echo "Release blocked: $CEF_RELEASE has no $arch archive ($url). Publish it with scripts/publish-cef.sh." >&2
    exit 2
  elif [ "$code" != 200 ]; then
    echo "warning: couldn't check $url (HTTP $code)" >&2
  fi
done
exit 0
