#!/bin/bash
# Launch the built app three times on a throwaway data folder (no pages, a page opened, the page
# restored) and quit it each time like ⌘Q, just after a settings write or resize. Fails if it dies, hangs,
# exits with an error or leaves a crash report: the only check that sees a CHECK inside Chromium.
#   Tests/smoke-launch.sh [path/to/Cra.app]     (default build/Cra.app)
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-build/Cra.app}"
EXE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
TEST_DIR="$(mktemp -d /tmp/cra-smoke.XXXXXX)"
DATA="$TEST_DIR/data"
REPORTS="$HOME/Library/Logs/DiagnosticReports"
mkdir -p "$DATA"
touch "$TEST_DIR/started"
PID=""
cleanup() {
  [ -n "$PID" ] && kill -9 "$PID" 2>/dev/null || true
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

fail() {
  echo "Smoke: FAIL: $*"
  echo "--- last lines of the app's output"
  tail -40 "$TEST_DIR/run-"*.log 2>/dev/null || true
  exit 1
}

# Seeds an off-centre frame on the secondary display when present, or quits like
# ⌘Q: an Apple event to this pid only, never to the installed Cra.
cat > "$TEST_DIR/quit.swift" <<'EOF'
import AppKit
if CommandLine.arguments[1] == "frame" {
    let _ = NSApplication.shared
    let screen = NSScreen.screens.last!.visibleFrame
    let size = NSSize(width: min(1000, max(640, screen.width - 160)),
                      height: min(700, max(420, screen.height - 180)))
    let frame = NSRect(x: screen.minX + floor((screen.width - size.width) / 3),
                       y: screen.minY + floor((screen.height - size.height) / 3),
                       width: size.width, height: size.height)
    let json = try! JSONSerialization.data(withJSONObject: ["windows": [["frame": NSStringFromRect(frame)]]])
    print(String(decoding: json, as: UTF8.self))
    exit(0)
}
let pid = pid_t(CommandLine.arguments[1])!
exit(NSRunningApplication(processIdentifier: pid)?.terminate() == true ? 0 : 1)
EOF
xcrun swiftc "$TEST_DIR/quit.swift" -o "$TEST_DIR/quit"

# Past onboarding, no quit warning, and not reading Arc's preferences on this machine.
cat > "$DATA/settings.json" <<'EOF'
{"hasSeenImportPrompt": true, "warnBeforeQuitting": false, "toolbarDefaultMigrated": true, "showToolbar": false}
EOF
"$TEST_DIR/quit" frame > "$DATA/windows.json"
cat > "$TEST_DIR/page.html" <<'EOF'
<!doctype html><title>Smoke</title><p>Cra smoke test</p>
EOF

run() {
  local n="$1" what="$2"
  cp "$DATA/windows.json" "$TEST_DIR/expected-$n.json"
  CRA_DATA_DIR="$DATA" CRA_COMMAND_FILE="$TEST_DIR/commands" CRA_TEST_BACKGROUND=1 \
    "$APP/Contents/MacOS/$EXE" > "$TEST_DIR/run-$n.log" 2>&1 &
  PID=$!
  # The command file appears once the app has finished launching.
  for _ in $(seq 120); do
    [ -e "$TEST_DIR/commands" ] && break
    kill -0 "$PID" 2>/dev/null || fail "launch $n ($what): the app exited while starting"
    sleep 0.5
  done
  [ -e "$TEST_DIR/commands" ] || fail "launch $n ($what): not ready after 60 s"
  [ "$what" = "opens a page" ] && echo "cra://open?url=file://$TEST_DIR/page.html" >> "$TEST_DIR/commands"
  sleep 8
  kill -0 "$PID" 2>/dev/null || fail "launch $n ($what): the app died before quitting"
  echo "cra://debug?windows=1" >> "$TEST_DIR/commands"
  for _ in $(seq 50); do
    grep -q 'Cra windows: MainWindowController' "$TEST_DIR/run-$n.log" && break
    sleep 0.1
  done
  python3 - "$TEST_DIR/expected-$n.json" "$TEST_DIR/run-$n.log" <<'PY' || fail "launch $n ($what): the window moved or resized on launch"
import json, re, sys
expected = json.load(open(sys.argv[1]))["windows"][0]["frame"]
match = re.search(r"Cra windows: MainWindowController .*? frame=(.*?) parent=", open(sys.argv[2]).read())
def numbers(frame):
    return [float(n) for n in re.findall(r"-?[0-9]+(?:\.[0-9]+)?", frame)]
assert match, "No browser window"
assert numbers(match[1]) == numbers(expected), (expected, match[1])
PY
  # A settings write just before quitting (#36 crashed on one at quit).
  echo "cra://action/toggleToolbar" >> "$TEST_DIR/commands"
  sleep 0.3
  if [ "$n" = 2 ]; then
    # Both commands run in the same poll, before the 300 ms frame debounce.
    local resized
    resized=$(python3 - "$TEST_DIR/expected-$n.json" <<'PY'
import json, re, sys
value = json.load(open(sys.argv[1]))["windows"][0]["frame"]
x, y, width, height = [float(n) for n in re.findall(r"-?[0-9]+(?:\.[0-9]+)?", value)]
print(f"{max(640, width - 87):g}x{max(420, height - 53):g}")
PY
)
    printf '%s\n' "cra://debug?windowSize=$resized" 'cra://debug?quit=1' >> "$TEST_DIR/commands"
  else
    "$TEST_DIR/quit" "$PID" || fail "launch $n ($what): the app did not take the quit event"
  fi
  for _ in $(seq 60); do
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.5
  done
  kill -0 "$PID" 2>/dev/null && fail "launch $n ($what): still running 30 s after quitting"
  local status=0
  wait "$PID" || status=$?
  PID=""
  rm -f "$TEST_DIR/commands"
  [ "$status" = 0 ] || fail "launch $n ($what): exited with status $status"
  if [ "$n" = 2 ]; then
    python3 - "$DATA/windows.json" "$TEST_DIR/expected-$n.json" <<'PY' || fail "the last resize was lost at quit"
import json, re, sys
def frame(path):
    value = json.load(open(path))["windows"][0]["frame"]
    return [float(n) for n in re.findall(r"-?[0-9]+(?:\.[0-9]+)?", value)]
before = frame(sys.argv[2])
width, height = max(640, before[2] - 87), max(420, before[3] - 53)
expected = [before[0], before[1] + before[3] - height, width, height]
assert frame(sys.argv[1]) == expected, (frame(sys.argv[1]), expected)
PY
  fi
  echo "Smoke: launch $n $what and quits cleanly"
}

run 1 "starts with no pages"
run 2 "opens a page"
run 3 "restores the page"
sleep 3  # ReportCrash writes a moment after the process is gone
CRASHES="$(find "$REPORTS" -maxdepth 1 -name "$EXE*.ips" -newer "$TEST_DIR/started" 2>/dev/null || true)"
[ -z "$CRASHES" ] || fail "crash reports were written:"$'\n'"$CRASHES"
echo "Smoke: passed"
