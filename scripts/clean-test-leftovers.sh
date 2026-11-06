#!/bin/bash
# Removes what Cra test runs leave behind on this Mac, which otherwise fills the disk:
#
#   1. code sign clones: Chromium copies a running app bundle into
#      $(getconf DARWIN_USER_TEMP_DIR)/../X/<bundle id>.code_sign_clone and deletes the copy on
#      a normal quit. A killed or crashed test copy leaves it (300 MB–1 GB each). Clones of any
#      app (Chrome too) go, as long as no process has them open. macOS drops them at reboot anyway.
#   2. per-bundle data of Cra test copies (bundle ids dk.kildahl.cra*, dk.kildahl.test.*,
#      app.crabrowser.*, dev.cra.*, app.cra.*): Caches, HTTPStorages, WebKit, Saved Application
#      State, Preferences and the per-user temp/cache folders. Never the installed Cra's own ids,
#      never CraClip (dk.kildahl.cra.clip), never an app that is running.
#   3. Claude Code scratchpads of this repo's finished sessions (main checkout and ../cra-wt-*
#      worktrees): test bundles, data folders, recordings. A session's folder goes once nothing
#      in it changed for --scratch-hours (default 24) and no process has a file in it open.
#   4. LaunchServices entries of Cra bundles that no longer exist.
#
# Usage:
#   scripts/clean-test-leftovers.sh [--dry-run] [--scratch-hours N] [--keep-session ID]
#   scripts/clean-test-leftovers.sh --hook      # Claude Code Stop hook: detaches, at most every 30 min
#
# Anything touched in the last hour is left alone, so a test copy that is starting up keeps its
# files. Safe to run while other sessions test: running apps and open files are skipped.
set -u

DRY=0
SCRATCH_HOURS=24
KEEP_SESSION=""
HOOK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --scratch-hours) SCRATCH_HOURS="$2"; shift ;;
    --keep-session) KEEP_SESSION="$2"; shift ;;
    --hook) HOOK=1 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
  esac
  shift
done

USER_TEMP="$(cd "$(getconf DARWIN_USER_TEMP_DIR)" && pwd -P)"   # …/T
VAR_USER="$(dirname "$USER_TEMP")"                                # …/<hash>
STATE="$USER_TEMP/cra-clean-test-leftovers"
LOG="$STATE.log"

if [ "$HOOK" = 1 ]; then
  # The Stop hook passes {"session_id": …} on stdin. Return at once; the work runs detached.
  session="$(sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$(find "$STATE.stamp" -mmin -30 2>/dev/null)" ] && exit 0
  touch "$STATE.stamp"
  nohup "$0" --keep-session "$session" >"$LOG" 2>&1 </dev/null &
  exit 0
fi

# One run at a time (a lock older than an hour is from a run that died).
LOCK="$STATE.lock"
[ -n "$(find "$LOCK" -maxdepth 0 -mmin +60 2>/dev/null)" ] && rmdir "$LOCK" 2>/dev/null
mkdir "$LOCK" 2>/dev/null || { echo "another cleanup is running"; exit 0; }
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
TEST_ID_RE='^(dk\.kildahl\.(cra|test\.)|app\.crabrowser\.|dev\.cra\.|app\.cra\.)'
WORK="$(mktemp -d "$USER_TEMP/cra-clean.XXXXXX")"
trap 'rmdir "$LOCK" 2>/dev/null; rm -rf "$WORK"' EXIT

say() { echo "$@"; }
remove() {   # remove <path>…
  for p in "$@"; do
    [ -e "$p" ] || [ -L "$p" ] || continue
    if [ "$DRY" = 1 ]; then say "would remove $p"; else rm -rf "$p" && say "removed $p"; fi
  done
}
recent() { [ -n "$(find "$1" -maxdepth 0 -mmin -60 2>/dev/null)" ]; }   # touched in the last hour
free_kb() { df -k "$HOME" | awk 'NR==2 {print $4}'; }
before="$(free_kb)"

scratch_root="$(cd "/tmp/claude-$(id -u)" 2>/dev/null && pwd -P)"

# Everything under the cleaned folders that a process of this user has open, is in or runs.
{ lsof -nP -Fn 2>/dev/null | sed -n 's/^n//p'; ps -axww -o command=; } |
  grep -F -e "$VAR_USER" -e "$HOME/Library" -e "/tmp/claude-" | sort -u >"$WORK/in-use"
# A process running from a code sign clone shows up under the clone's path only through +D
# (a plain lsof names the original bundle, whose blocks the clone shares).
lsof -nP -Fn +D "$VAR_USER/X" 2>/dev/null | sed -n 's/^n//p' >>"$WORK/in-use"
lsappinfo list 2>/dev/null | sed -n 's/.*bundleID="\([^"]*\)".*/\1/p' | sort -u >"$WORK/running-ids"
in_use() { grep -qF -- "$1" "$WORK/in-use"; }

# Ids that must never be cleaned: the installed Cra's bundles, CraClip, and running apps.
{
  find /Applications/Cra.app -maxdepth 6 -name Info.plist 2>/dev/null |
    while read -r plist; do /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null; done
  printf '%s\n' dk.kildahl.cra dk.kildahl.cra.docktile dk.kildahl.cra.clip
  lsappinfo list 2>/dev/null | sed -n 's/.*bundleID="\([^"]*\)".*/\1/p'
} | sort -u >"$WORK/keep-ids"
protected() {   # protected <id>: a kept id, a helper of one, or one of the installed Cra's parts
  local base="${1%%.helper*}"
  grep -qxF -- "$1" "$WORK/keep-ids" || grep -qxF -- "$base" "$WORK/keep-ids" ||
    case "$1" in dk.kildahl.cra.helper*|dk.kildahl.cra.clip.*) return 0 ;; *) return 1 ;; esac
}

# 1. Code sign clones nobody has open.
for dir in "$VAR_USER"/X/*.code_sign_clone; do
  [ -d "$dir" ] || continue
  newest=""
  if grep -qxF -- "$(basename "$dir" .code_sign_clone)" "$WORK/running-ids"; then
    newest="$(ls -td "$dir"/* 2>/dev/null | head -1)"   # a running app's own clone, in case lsof missed it
  fi
  for clone in "$dir"/*; do
    [ -e "$clone" ] || continue
    [ "$clone" = "$newest" ] && continue
    recent "$clone" && continue
    in_use "$clone" && continue
    remove "$clone"
  done
done

# 2. Per-bundle data of Cra test copies.
for loc in "$HOME/Library/Caches" "$HOME/Library/HTTPStorages" "$HOME/Library/WebKit" \
           "$HOME/Library/Saved Application State" "$HOME/Library/Preferences" \
           "$VAR_USER/C" "$VAR_USER/T"; do
  [ -d "$loc" ] || continue
  ls "$loc" | grep -iE "$TEST_ID_RE" | while read -r name; do
    item="$loc/$name"
    id="${name%.savedState}"; id="${id%.plist}"; id="${id%.binarycookies}"
    if [ "$loc" = "$VAR_USER/T" ] || [ "$loc" = "$VAR_USER/C" ]; then
      # Temp items are named <bundle id>.<random> (the installed Cra makes dk.kildahl.cra.AbC123).
      id="$(echo "$id" | sed -E 's/\.chromium_chrome_url_fetcher_\..*$//; s/\.[A-Za-z0-9]{6}$//')"
    fi
    protected "$id" && continue
    recent "$item" && continue
    in_use "$item" && continue
    if [ "$loc" = "$HOME/Library/Preferences" ] && [ "$DRY" = 0 ]; then
      defaults delete "$id" >/dev/null 2>&1   # keeps cfprefsd's cache in step with the file
    fi
    remove "$item"
  done
done

# 3. Scratchpads of this repo's finished sessions.
repo="$(cd "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)/.." && pwd -P)"
slug="$(echo "$repo" | sed 's#[/.]#-#g')"
if [ -n "$scratch_root" ]; then
  for project in "$scratch_root/$slug" "$scratch_root/$slug"-wt-* "$scratch_root/$slug"--claude-worktrees-*; do
    [ -d "$project" ] || continue
    for session in "$project"/*/; do
      session="${session%/}"
      [ -n "$KEEP_SESSION" ] && [ "$(basename "$session")" = "$KEEP_SESSION" ] && continue
      [ -n "$(find "$session" -mmin "-$((SCRATCH_HOURS * 60))" -print -quit 2>/dev/null)" ] && continue
      in_use "$session/" && continue
      remove "$session"
    done
  done
fi

# 4. LaunchServices entries of Cra bundles that are gone (helpers are registered on their own).
"$LSREGISTER" -dump 2>/dev/null |
  sed -n 's/^path: *\(.*\.app\) (0x[0-9a-f]*)$/\1/p' | sort -u |
  grep -iE "cra|/tmp/claude-|/private/tmp/claude-" |
  while read -r app; do
    [ -e "$app" ] && continue
    if [ "$DRY" = 1 ]; then say "would unregister $app"; else "$LSREGISTER" -u "$app" 2>/dev/null; say "unregistered $app"; fi
  done

after="$(free_kb)"
say "free space: $((before / 1048576)) GB → $((after / 1048576)) GB"
