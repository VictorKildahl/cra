#!/bin/bash
# rounds.sh [browser...]: five rounds of each browser (default: cra helium arc dia), the order rotating each round:
# a measured session, then a Speedometer session. Results in $XBENCH_OUT (default $XBENCH_DIR/results); a session
# already there with a tab switch measured is kept, so the script can be run again to fill in what failed.
# Each run waits for 30 s without input first (nobody at the Mac; this script's own keys reset the counter, so it
# pauses 35 s).
B="${XBENCH_DIR:-$HOME/CraBench}"; HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$B"
OUT="${XBENCH_OUT:-$B/results}"; mkdir -p "$OUT"
NAMES=("$@"); [ ${#NAMES[@]} -gt 0 ] || NAMES=(cra helium arc dia)
idle() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'; }
gate() { sleep 35; for i in $(seq 1 2000); do [ "$(idle)" -ge 30 ] && return; sleep 10; done; }
n=${#NAMES[@]}
for r in 1 2 3 4 5; do
  for i in $(seq 0 $((n-1))); do
    b=${NAMES[$(( (i + r - 1) % n ))]}
    # Up to three tries each: now and then a browser's bar takes Return before it has caught up with the URL and
    # opens a search instead of the bench page.
    for try in 1 2 3; do
      [ -f "$OUT/$b-$r/result.json" ] && grep -q tab_switch "$OUT/$b-$r/result.json" && break
      rm -rf "$OUT/$b-$r"
      gate; python3 "$HERE/xbench.py" session $b "$OUT/$b-$r" > "$OUT/$b-$r.log" 2>&1
    done
    for try in 1 2 3; do
      [ -f "$OUT/sp-$b-$r/result.json" ] && grep -q speedometer "$OUT/sp-$b-$r/result.json" && break
      rm -rf "$OUT/sp-$b-$r"
      gate; python3 "$HERE/xbench.py" speedometer $b "$OUT/sp-$b-$r" > "$OUT/sp-$b-$r.log" 2>&1
    done
  done
done
echo DONE > "$OUT/done"
