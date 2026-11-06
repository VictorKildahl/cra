#!/usr/bin/env bash
# Claude Code PreToolUse hook (Bash): before a `git push`, checks that the commit being pushed
# keeps every test that pins a shipped issue's behaviour as Tests/promises.lock has it
# (scripts/promises.py). Blocks (exit 2) when one changed without the lock. CI runs the same check
# through scripts/test.sh, but after the push; sessions push straight to main.
set -euo pipefail

input="$(cat)"
command="$(jq -r '.tool_input.command // empty' <<<"$input")"
# Only an actual `git push` (at the start of a command, maybe after VAR=… prefixes or `git -C dir`).
grep -qE '(^|[;&|(]|\$\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=("[^"]*"|[^[:space:]]+)[[:space:]]+)*git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?push\b' <<<"$command" || exit 0

# The repository the push runs in: `git -C dir`, else a leading `cd dir &&`, else the hook's cwd.
dir="$(jq -r '.cwd // empty' <<<"$input")"
if [[ "$command" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+)[[:space:]]+push ]]; then dir="${BASH_REMATCH[1]}"
elif [[ "$command" =~ ^[[:space:]]*cd[[:space:]]+([^[:space:];&]+) ]]; then dir="${BASH_REMATCH[1]}"; fi
dir="${dir/#\~/$HOME}"; dir="${dir//\"/}"; dir="${dir//\'/}"
repo="$(git -C "${dir:-.}" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -x "$repo/scripts/promises.py" ]] || exit 0

if ! out="$("$repo/scripts/promises.py" --rev HEAD 2>&1)"; then
  echo "$out" >&2
  exit 2
fi
