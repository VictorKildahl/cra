# Helpers for recording release-note clips from a test copy of Cra. Source it:
#
#   source scripts/clips/clip.sh      # builds the tools and CraClip.app on first use
#   reset                             # fresh demo profile, relaunch CraClip, sets WX WY WW WH
#   guard && rec reorder 6 && glide w:300 m:$((WX+113)),$((WY+676)),800 d m:...,1400 u; waitrec
#
# Then encode with cra-website's scripts/release-clip.sh (FPS=120 for these recordings).
# CraClip is a renamed copy of /Applications/Cra.app (bundle id dk.kildahl.cra.clip) with its
# own CRA_DATA_DIR, so it never touches the real Cra; drive it with CRA_COMMAND_FILE lines
# (`cmd`), plain keys (`key`), ⌘ shortcuts via cliclick, and the pointer via `glide`.
# Everything here moves the real pointer and keyboard: only run it when Victor has handed
# over the screen, and ask other sessions (ListAgents + SendMessage) to pause their input.

CLIPS_SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CLIPS="${CLIPS:-$CLIPS_SRC/../../build/clips}"
mkdir -p "$CLIPS/bin" "$CLIPS/rec"
R="$CLIPS/rec"

for tool in record glide key keys-up; do
  [[ "$CLIPS/bin/$tool" -nt "$CLIPS_SRC/$tool.swift" ]] || swiftc -O "$CLIPS_SRC/$tool.swift" -o "$CLIPS/bin/$tool" || return 1
done

APP="$CLIPS/CraClip.app"
if [[ ! -d "$APP" ]]; then
  ditto /Applications/Cra.app "$APP"
  (
    cd "$APP/Contents" && mv MacOS/Cra MacOS/CraClip
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable CraClip" -c "Set :CFBundleIdentifier dk.kildahl.cra.clip" -c "Set :CFBundleName CraClip" Info.plist
    /usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" Info.plist 2>/dev/null
    cd Frameworks
    for h in "Cra Helper"*.app; do
      n="${h/Cra Helper/CraClip Helper}" && mv "$h" "$n"
      mv "$n/Contents/MacOS/${h%.app}" "$n/Contents/MacOS/${n%.app}"
      id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$n/Contents/Info.plist")
      /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${n%.app}" -c "Set :CFBundleName ${n%.app}" \
        -c "Set :CFBundleIdentifier ${id/dk.kildahl.cra/dk.kildahl.cra.clip}" "$n/Contents/Info.plist"
    done
  )
  codesign --force --deep -s - "$APP" >/dev/null 2>&1
  defaults write dk.kildahl.cra.clip SUEnableAutomaticChecks -bool NO
fi

nap() { perl -e "select(undef,undef,undef,$1)"; }
cmd() { for c in "$@"; do echo "$c" >> "$CLIPS/commands.txt"; done; }
glide() { "$CLIPS/bin/glide" "$@"; }
key() { "$CLIPS/bin/key" "$@"; }
keys_up() { "$CLIPS/bin/keys-up"; }
clip_pid() { pgrep -f "CraClip.app/Contents/MacOS/CraClip$"; }
idle() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'; }
isfront() { [[ "$(osascript -e 'tell application "System Events" to unix id of first process whose frontmost is true')" == "$PID" ]]; }

# Quits CraClip, writes a fresh demo profile and relaunches it; waits $1 s (default 3) for pages.
reset() {
  osascript -e 'tell application id "dk.kildahl.cra.clip" to quit' >/dev/null 2>&1
  for _ in $(seq 1 15); do clip_pid >/dev/null || break; nap 0.5; done
  rm -rf "$CLIPS/data"
  python3 "$CLIPS_SRC/seed-demo.py" "$CLIPS/data" "{{540, 60}, {1100, 700}}" >/dev/null
  : > "$CLIPS/commands.txt"
  # Clips are framed for the display in use, not the CRA_TEST_SCREEN one test runs use.
  (env -u CRA_TEST_SCREEN CRA_DATA_DIR="$CLIPS/data" CRA_COMMAND_FILE="$CLIPS/commands.txt" "$APP/Contents/MacOS/CraClip" > "$CLIPS/craclip.log" 2>&1 &)
  nap 5
  PID=$(clip_pid)
  # The largest window is the main one; Chromium's page windows are AX windows too.
  read -r WX WY WW WH < <(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID)
    set best to \"\"
    set area to 0
    repeat with win in windows
      set {x, y} to position of win
      set {w, h} to size of win
      if w * h > area then
        set area to w * h
        set best to (x as text) & \" \" & (y as text) & \" \" & (w as text) & \" \" & (h as text)
      end if
    end repeat
    return best
  end tell")
  nap "${1:-3}"
}

# Makes CraClip's main window key and checks it is frontmost before sending input.
guard() { cmd "cra://action/stop"; nap 0.6; isfront || { echo "CraClip is not frontmost" >&2; return 1; }; }

# rec <name> <seconds> [x,y,w,h]: records in the background; follow with waitrec.
rec() {
  "$CLIPS/bin/record" "$PID" "$2" "$R/$1.mov" ${3:-} > "$R/$1.log" 2>&1 & RECPID=$!
  ( perl -e "sleep($2+6)"; kill $RECPID 2>/dev/null ) &
  nap 0.8
}
waitrec() { wait $RECPID; keys_up; }

# Quit CraClip when done; it can come to the front on Victor's screen.
clip_quit() { osascript -e 'tell application id "dk.kildahl.cra.clip" to quit' >/dev/null 2>&1; }
