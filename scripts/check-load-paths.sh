#!/bin/bash
# Load paths that point outside an app bundle and the system: an LC_RPATH, or a library loaded by an absolute path
# that isn't /usr/lib or /System (a toolchain on the build Mac, a Homebrew prefix). Such a path doesn't exist on the
# user's Mac. SwiftPM links Cra's own binaries with an rpath into the toolchain that built them
# (/Applications/Xcode….app/…/usr/lib/swift-6.2/macosx, for back-deployed Swift libraries Cra doesn't load), and
# Sparkle loads through @rpath, so that path came first: syspolicy_check called it a fatal "Bad Load Command" and
# macOS's malware check failed on Intel Macs (GitHub #720, 0.1.54).
#   scripts/check-load-paths.sh <App.app>          fails, naming each such path
#   scripts/check-load-paths.sh --strip <file>…    deletes toolchain rpaths from those Mach-O files (before signing)
# scripts/build.sh strips Cra's binaries and checks the bundle on every build; scripts/test-load-paths.sh tests both.
set -euo pipefail
# otool reads "name(member)" as an archive member, and Chrome's helpers end in "(Alerts)", "(GPU)": it reads a link.
LINK="$(mktemp -d)/macho"
trap 'rm -rf "$(dirname "$LINK")"' EXIT
# Every LC_RPATH and loaded library path of a Mach-O file, whole (spaces too: "path /Applications/Xcode 26.app/…").
paths() {
  ln -sf "$1" "$LINK"
  otool -l "$LINK" | awk -v want="$2" '
    /cmd LC_RPATH/ || (want == "all" && /cmd LC_(LOAD|LOAD_WEAK|REEXPORT|LAZY_LOAD)_DYLIB/) {
      getline; getline; sub(/^ *(path|name) /, ""); sub(/ \(offset [0-9]+\)$/, ""); print }'
}

if [ "${1:-}" = --strip ]; then
  shift
  for f in "$@"; do
    [ -f "$f" ] || continue
    while IFS= read -r rpath; do
      [ -n "$rpath" ] && install_name_tool -delete_rpath "$rpath" "$f"
    done < <(paths "$f" rpaths | grep -E '\.xctoolchain|/Xcode[^/]*\.app/' || true)
  done
  exit 0
fi

APP="$(cd "${1:?usage: check-load-paths.sh <App.app> | --strip <file>…}" && pwd)"
bad=0
while IFS= read -r -d '' f; do
  file -b "$f" | grep -q 'Mach-O' || continue
  while IFS= read -r p; do
    case "$p" in
      ''|@*|/usr/lib/*|/System/*) ;;
      *) echo "${f#"$APP"/} points outside the app: $p" >&2; bad=1 ;;
    esac
  done < <(paths "$f" all)
done < <(find "$APP" -type f \( -perm -u+x -o -name '*.dylib' \) -print0)
[ "$bad" = 0 ] || { echo "Load paths outside $APP (GitHub #720)" >&2; exit 1; }
