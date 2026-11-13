#!/bin/bash
# Measures one session of a Cra build on a local bench page (docs/speed.md), in a background copy
# with its own data folder, from outside the app. Two launches:
#   idle:    memory (phys_footprint over the process tree) at 1, 10 and 20 tabs, 3 minutes after the
#            20th ("settled"), and 30 s after closing back to 1; idle CPU and wakeups at 1 and 20 tabs.
#            No HitchMonitor here: its 4 ms ping alone is ~250 wakeups/s.
#   latency: new tab -> first contentful paint, tab switch -> shown (visibilitychange, then 2
#            requestAnimationFrame), each timed from the command's HitchMonitor mark.
#   procs:   20 tabs, then each process's footprint and --type (procs.txt), and the windows (windows.txt).
#
#   scripts/perf/bench.sh build/Cra.app build/perf/<label>
#   MODES="idle latency" (default)  IDLE=<seconds> (default 30)  BENCH_ENV="K=V ..." (passed to Cra)
#   BENCH_ARGS="--disable-features=X,Y" (Chromium switches on Cra's command line; Cra appends its own)
#
# Compare builds with scripts/perf/rounds.sh (interleaved), read with scripts/perf/report.py.
# Traps: test copies open on CRA_TEST_SCREEN; a display asleep or showing another Space gives their
# windows no frames, so `caffeinate -d` and a screen that is on. A switch never shown counts as
# missing in report.py's "switch n": rerun then.
set -uo pipefail
APP="$1"; ROOT_OUT="$2"; IDLE="${IDLE:-30}"
B="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$B/../../build/perf"
mkdir -p "$TOOLS"
[ "$TOOLS/fp" -nt "$B/fp.swift" ] || xcrun swiftc -O "$B/fp.swift" -o "$TOOLS/fp" || exit 1
FP="$TOOLS/fp"

run() {
  local MODE="$1" OUT="$ROOT_OUT/$1"
  rm -rf "$OUT"; mkdir -p "$OUT"; : > "$OUT/marks.jsonl"; : > "$OUT/result.jsonl"
  local DATA; DATA="$(cd "$(mktemp -d /tmp/cra-bench.XXXXXX)" && pwd -P)"
  echo '{"hasSeenImportPrompt": true, "toolbarDefaultMigrated": true, "showToolbar": false, "disabledDefaultDeveloperHosts": ["127.0.0.1"]}' > "$DATA/settings.json"
  python3 -I -u "$B/server.py" "$B/pages" 0 "$OUT/marks.jsonl" > "$OUT/port" 2>"$OUT/server.err" &
  local SRV=$! PORT=""
  for _ in $(seq 50); do PORT=$(head -1 "$OUT/port"); [ -n "$PORT" ] && break; sleep 0.1; done
  local PAGE="http://127.0.0.1:$PORT/bench.html" CMD="$OUT/commands" HITCH=""
  : > "$CMD"
  [ "$MODE" = latency ] && HITCH="$OUT/hitch.log"
  env CRA_DATA_DIR="$DATA" CRA_COMMAND_FILE="$CMD" CRA_HITCH_LOG="$HITCH" CRA_TEST_BACKGROUND=1 ${BENCH_ENV:-} \
    "$APP/Contents/MacOS/Cra" -ApplePersistenceIgnoreState YES --disable-backgrounding-occluded-windows --mute-audio ${BENCH_ARGS:-} \
    > "$OUT/stdout.log" 2>&1 &
  local PID=$!
  for _ in $(seq 150); do grep -q "pid $PID reads commands" "$DATA"/cra*.log 2>/dev/null && break; sleep 0.2; done
  python3 -I -c 'import time; print(time.time() - time.clock_gettime(time.CLOCK_UPTIME_RAW))' > "$OUT/clock-offset"
  send() { printf '%s\n' "$1" >> "$CMD"; }
  snap() { echo "{\"at\":\"$1\",\"t\":$(python3 -I -c 'import time;print(time.time())'),\"m\":$("$FP" $PID)}" >> "$OUT/result.jsonl"; }
  if [ "$MODE" = idle ]; then
    send "cra://open?url=$PAGE?n=1"; sleep 30; snap mem1
    snap idle1-start; sleep "$IDLE"; snap idle1-end
    for i in $(seq 2 10); do send "cra://open?url=$PAGE?n=$i"; sleep 1.5; done; sleep 10; snap mem10
    for i in $(seq 11 20); do send "cra://open?url=$PAGE?n=$i"; sleep 1.5; done; sleep 15; snap mem20
    snap idle20-start; sleep "$IDLE"; snap idle20-end
    sleep 150; snap mem20settled; "$B/procs.sh" "$FP" $PID > "$OUT/procs20.txt"
    for i in $(seq 1 19); do send "cra://action/closeTab"; sleep 0.4; done; sleep 30; snap memback1
  elif [ "$MODE" = procs ]; then
    for i in $(seq 1 20); do send "cra://open?url=$PAGE?n=$i"; sleep 1.5; done; sleep 20
    "$B/procs.sh" "$FP" $PID > "$OUT/procs.txt"
    R=$(awk '/--type=renderer/ {print $4; exit}' "$OUT/procs.txt"); [ -n "$R" ] && vmmap --summary "$R" > "$OUT/renderer-vmmap.txt" 2>/dev/null
    send "cra://debug?freezingState=1"; sleep 2
  else
    send "cra://open?url=$PAGE?n=1"; sleep 5
    for i in $(seq 2 20); do send "cra://open?url=$PAGE?n=$i"; sleep 1.5; done; sleep 5
    for i in $(seq 1 16); do send "cra://action/nextTab"; sleep 1.2; done
    sleep 2
  fi
  send "cra://debug?quit=1"; for _ in $(seq 100); do kill -0 $PID 2>/dev/null || break; sleep 0.2; done
  kill -KILL $PID 2>/dev/null; kill $SRV 2>/dev/null; wait $SRV 2>/dev/null
  cp "$DATA"/cra*.log "$OUT/" 2>/dev/null; rm -rf "$DATA"
}
for m in ${MODES:-idle latency}; do run "$m"; done
echo "done $ROOT_OUT"
