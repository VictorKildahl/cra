#!/bin/bash
# What a user waits for, on a real sidebar and real sites (docs/speed.md, "Measure what users feel"):
# tab switches, space switches, sidebar toggles, command-bar keystrokes, opening and closing tabs.
# A background copy of the app with a copy of a data folder's sidebar.json, settings.json and
# windows.json (no Chromium profile: nothing signed in), driven through CRA_COMMAND_FILE, timed by
# HitchMonitor: per action, the main-thread stalls until the next action and the time to the next
# "page-shown" mark. `sample` stacks of the main thread are taken during the tab switches and the
# command-bar typing.
#
#   scripts/perf/journeys.sh <app> <out dir> [data folder to copy from, default Cra's own]
#   then: python3 scripts/perf/journeys.py <out dir>...
set -uo pipefail
APP="$1"; OUT="$2"; FROM="${3:-$HOME/Library/Application Support/Cra}"
rm -rf "$OUT"; mkdir -p "$OUT"
DATA="$(cd "$(mktemp -d /tmp/cra-journeys.XXXXXX)" && pwd -P)"
for f in sidebar.json settings.json windows.json; do [ -f "$FROM/$f" ] && cp "$FROM/$f" "$DATA/"; done
CMD="$OUT/commands"; HITCH="$OUT/hitch.log"; : > "$CMD"
CRA_DATA_DIR="$DATA" CRA_COMMAND_FILE="$CMD" CRA_HITCH_LOG="$HITCH" CRA_TEST_BACKGROUND=1 \
  "$APP/Contents/MacOS/Cra" -ApplePersistenceIgnoreState YES --disable-backgrounding-occluded-windows --mute-audio \
  > "$OUT/stdout.log" 2>&1 &
PID=$!
trap 'kill -KILL $PID 2>/dev/null; cp "$DATA"/cra*.log "$OUT/" 2>/dev/null; rm -rf "$DATA"' EXIT
for _ in $(seq 150); do grep -q "pid $PID reads commands" "$DATA"/cra*.log 2>/dev/null && break; sleep 0.2; done
send() { printf '%s\n' "$1" >> "$CMD"; sleep "${2:-1.2}"; }
sleep 15   # restore settles
SITES="https://en.wikipedia.org/wiki/Web_browser https://news.ycombinator.com https://github.com/chromiumembedded/cef
https://developer.apple.com/documentation/appkit https://www.bbc.com/news https://www.theverge.com
https://stackoverflow.com/questions https://www.youtube.com https://www.reddit.com/r/macapps https://www.figma.com"
for s in $SITES; do send "cra://open?url=$s" 2; done
sleep 10
sample $PID 20 1 -file "$OUT/sample-switch.txt" >/dev/null 2>&1 &
SAMPLER=$!
for i in $(seq 20); do send "cra://action/nextTab"; done
wait $SAMPLER 2>/dev/null   # never a bare wait: Cra is a background job too
sample $PID 18 1 -file "$OUT/sample-space-sidebar.txt" >/dev/null 2>&1 &
SAMPLER=$!
for i in $(seq 6); do send "cra://action/nextSpace" 1.5; done
for i in $(seq 6); do send "cra://action/toggleSidebar" 1.2; done
wait $SAMPLER 2>/dev/null
sample $PID 15 1 -file "$OUT/sample-commandbar.txt" >/dev/null 2>&1 &
SAMPLER=$!
for r in 1 2 3; do
  for q in g gi git gith githu github "github c" "github cr"; do send "cra://commandbar?query=${q// /%20}" 0.25; done
  send "cra://dismiss" 1
done
wait $SAMPLER 2>/dev/null
for i in $(seq 5); do send "cra://open?url=https://en.wikipedia.org/wiki/Special:Random" 2; done
for i in $(seq 5); do send "cra://action/closeTab" 1; done
send "cra://debug?perfReport=$OUT/perf.json" 2
send "cra://debug?quit=1" 0
for _ in $(seq 100); do kill -0 $PID 2>/dev/null || break; sleep 0.2; done
echo "done $OUT"
