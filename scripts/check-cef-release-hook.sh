#!/usr/bin/env bash
# Claude Code PreToolUse hook (Bash): before a release tag (vX.Y.Z) is pushed, checks that the
# release ships the newest engine (the file keeps its CEF-era name: .claude/settings.json runs it). Blocks
# (exit 2) when
#   - Chrome's newest stable for macOS is newer than the engine scripts/fetch-engine.sh pins
#     (scripts/check-engine-update.sh --check), or
#   - the pinned ENGINE_RELEASE lacks the Apple silicon or the Intel archive on GitHub, so the
#     Release workflow's build.sh would fail to download it.
# CRA_ALLOW_OLD_ENGINE=1 on the push skips the first check (release.sh honours it too). With CRA_ENGINE=cef on the
# push, CEF's checks run instead (CRA_ALLOW_OLD_CEF=1). When the network can't be reached, it warns and lets the
# push through: release.sh checks again.
set -euo pipefail

command="$(jq -r '.tool_input.command // empty')"
# Only an actual `git push` of a release tag, as in check-release-media.sh.
grep -qE '(^|[;&|(]|\$\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=("[^"]*"|[^[:space:]]+)[[:space:]]+)*git[[:space:]]+push\b' <<<"$command" || exit 0
grep -qE '\bv[0-9]+\.[0-9]+\.[0-9]+\b' <<<"$command" || exit 0

repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
if grep -q 'CRA_ENGINE=cef' <<<"$command"; then
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
  assets=(); for arch in macosarm64 macosx64; do
    assets+=("https://github.com/VictorKildahl/cra/releases/download/${CEF_RELEASE}/cef_binary_${arch}_minimal.tar.bz2")
  done
  publish="scripts/publish-cef.sh"
else
  if ! grep -q 'CRA_ALLOW_OLD_ENGINE=1' <<<"$command"; then
    if ! out="$(scripts/check-engine-update.sh --check 2>&1)"; then
      if grep -q "Could not read" <<<"$out"; then
        echo "warning: couldn't read Chrome's version history; release.sh checks again" >&2
      else
        echo "$out" >&2
        echo "Release blocked: Chrome has a newer stable than the engine. Build it first (docs/chromium-engine.md), or push with CRA_ALLOW_OLD_ENGINE=1 for an urgent fix." >&2
        exit 2
      fi
    fi
  fi
  eval "$(grep -E '^(ENGINE_VERSION|ENGINE_RELEASE)=' scripts/fetch-engine.sh)"
  assets=(); for cpu in arm64 x64; do
    assets+=("https://github.com/VictorKildahl/cra/releases/download/${ENGINE_RELEASE}/cra_framework_${cpu}.tar.xz")
  done
  publish="scripts/publish-engine.sh"
fi

for url in "${assets[@]}"; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -I -L --max-time 15 "$url" || true)"
  if [ "$code" = 404 ]; then
    echo "Release blocked: no ${url##*/} at ${url%/*}. Publish it with $publish." >&2
    exit 2
  elif [ "$code" != 200 ]; then
    echo "warning: couldn't check $url (HTTP $code)" >&2
  fi
done
exit 0
