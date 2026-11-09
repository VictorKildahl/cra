#!/usr/bin/env bash
# Claude Code PreToolUse hook (Bash): before a release tag is pushed, checks that a release
# which changes the UI shows it in the release notes. Blocks (exit 2) when Sources/Cra/UI
# changed since the previous tag and the version's entry in cra-website's releases.ts has no
# `media:` clip. A release whose UI changes have nothing to film opts out with a comment in
# its entry: `// no clip: <reason>`. From 0.1.38 on, it also blocks a clip in an odd shape:
# the release page shows clips on an 11:7 stage, so each must be landscape 1.5-1.65:1, at
# least 1400 px wide and density 2 (cra-website's src/content/release-media-rules.ts).
set -euo pipefail

command="$(jq -r '.tool_input.command // empty')"
# Only an actual `git push` (at the start of a command, maybe after VAR=… prefixes),
# not text that mentions one.
grep -qE '(^|[;&|(]|\$\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=("[^"]*"|[^[:space:]]+)[[:space:]]+)*git[[:space:]]+push\b' <<<"$command" || exit 0
version="$(grep -oE '\bv[0-9]+\.[0-9]+\.[0-9]+\b' <<<"$command" | head -1)" || exit 0
[[ -n "$version" ]] || exit 0

repo="$(cd "$(dirname "$0")/../.." && pwd)"
releases="${CRA_WEBSITE:-$repo/../cra-website}/src/content/releases.ts"
[[ -f "$releases" ]] || exit 0

# The tag right below this version, and the tag itself if it exists yet (else HEAD).
previous="$(git -C "$repo" tag -l 'v*' | { cat; echo "$version"; } | sort -uV | grep -B1 -x "$version" | head -1)"
[[ -n "$previous" && "$previous" != "$version" ]] || exit 0
target="$version"; git -C "$repo" rev-parse -q --verify "refs/tags/$version" >/dev/null || target=HEAD
ui_changes="$(git -C "$repo" diff --name-only "$previous" "$target" -- Sources/Cra/UI)"
[[ -n "$ui_changes" ]] || exit 0

entry="$(awk -v v="${version#v}" '
  /^    version: "/ { inside = index($0, "\"" v "\"") > 0 }
  inside' "$releases")"

if [[ -z "$entry" ]]; then
  echo "Release $version has no entry in $releases yet. Add its release notes first (see docs/release.md)." >&2
  exit 2
fi
# Odd-shaped clips, for releases from 0.1.38 on (older ones shipped before the 11:7 stage).
if [[ "$(printf '%s\n' 0.1.38 "${version#v}" | sort -V | head -1)" == 0.1.38 ]]; then
  odd="$(awk '
    /media: \{/ { inside = 1; w = h = 0; d = 2; src = "" }
    inside && /src: "/ { src = $0; sub(/.*src: "/, "", src); sub(/".*/, "", src) }
    inside && /width: [0-9]/ { w = $0; gsub(/[^0-9]/, "", w) }
    inside && /height: [0-9]/ { h = $0; gsub(/[^0-9]/, "", h) }
    inside && /density: [0-9]/ { d = $0; sub(/.*density: /, "", d); sub(/,.*/, "", d) }
    inside && /^ *\},/ {
      inside = 0
      if (h > 0 && (w / h < 1.5 || w / h > 1.65 || w < 1400 || d + 0 != 2))
        printf "  %s is %d x %d, density %s\n", src, w, h, d
    }' <<<"$entry")"
  if [[ -n "$odd" ]]; then
    cat >&2 <<EOF
Release $version has clips in an odd shape for the release page's 11:7 stage:
$odd
Record the whole clip window (1100 x 700 pt) and encode it with cra-website's
scripts/release-clip.sh, which refuses other shapes: landscape 1.5-1.65:1, at least
1400 px wide, density 2.
EOF
    exit 2
  fi
fi

if grep -qE 'media: \{|// no clip:' <<<"$entry"; then
  exit 0
fi

cat >&2 <<EOF
Release $version changes the UI since $previous but its release notes have no clip:
$(sed 's/^/  /' <<<"$ui_changes" | head -15)

Record the visible change and attach it as \`media\` on the highlight in
$releases
(skill: release-clips; tools in scripts/clips/, encoder in cra-website/scripts/release-clip.sh).
If there is nothing to film, add \`// no clip: <reason>\` inside the $version entry.
EOF
exit 2
