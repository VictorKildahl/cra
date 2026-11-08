#!/bin/bash
# Installs or updates Cra from the latest GitHub release.
#   curl -fsSL https://raw.githubusercontent.com/VictorKildahl/cra/main/scripts/install.sh | bash
# Files downloaded with curl carry no quarantine flag, so macOS opens the
# unnotarized build without the Gatekeeper prompt a browser download triggers.
# Overrides: CRA_DOWNLOAD_URL (zip to install), CRA_INSTALL_DIR, CRA_NO_OPEN=1.
set -euo pipefail

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# Everything runs from main so a partially downloaded script never executes.
main() {
  [ "$(uname -s)" = Darwin ] || fail "Cra runs on macOS only."
  # hw.optional.arm64 is 1 on Apple silicon even when this shell runs under Rosetta.
  local asset=Cra-Intel.zip
  [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ] && asset=Cra.zip
  local url="${CRA_DOWNLOAD_URL:-https://github.com/VictorKildahl/cra/releases/latest/download/$asset}"
  local dir="${CRA_INSTALL_DIR:-}"

  [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "Cra needs macOS 14 Sonoma or later."

  if [ -z "$dir" ]; then
    if [ -w /Applications ]; then dir=/Applications; else dir="$HOME/Applications"; fi
  fi
  mkdir -p "$dir"

  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  say "Downloading Cra…"
  curl -fL --progress-bar -o "$TMP/Cra.zip" "$url" || fail "The download failed. Check your connection and run the command again."
  ditto -x -k "$TMP/Cra.zip" "$TMP" || fail "The download was damaged. Run the command again."
  [ -d "$TMP/Cra.app" ] || fail "The download did not contain Cra.app."

  if pgrep -xq Cra; then
    say "Quitting Cra to update it…"
    osascript -e 'quit app "Cra"' >/dev/null 2>&1 || true
    for _ in $(seq 20); do pgrep -xq Cra || break; sleep 0.5; done
    pgrep -xq Cra && fail "Cra is still running. Quit it and run the command again."
  fi

  rm -rf "$dir/Cra.app"
  mv "$TMP/Cra.app" "$dir/"
  xattr -dr com.apple.quarantine "$dir/Cra.app" 2>/dev/null || true

  say "Cra is installed in $dir. Run this command again any time to update."
  [ -n "${CRA_NO_OPEN:-}" ] || open "$dir/Cra.app"
}

main "$@"
