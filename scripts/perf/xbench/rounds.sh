#!/bin/bash
# Five rounds of every browser (order rotates each round): a measured session, then a Speedometer session.
# Each waits for 30 s without input first (nobody at the Mac; this script's own keys reset the counter, so it pauses 35 s).
B="${XBENCH_DIR:-$HOME/CraBench}"; HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$B"
OUT="$B/results"; mkdir -p $OUT
idle() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'; }
gate() { sleep 35; for i in $(seq 1 2000); do [ "$(idle)" -ge 30 ] && return; sleep 10; done; }
ORDERS=("cra helium arc dia" "helium arc dia cra" "arc dia cra helium" "dia cra helium arc" "cra arc helium dia")
for r in 1 2 3 4 5; do
  for b in ${ORDERS[$((r-1))]}; do
    [ -f "$OUT/$b-$r/result.json" ] && grep -q tab_switch "$OUT/$b-$r/result.json" && continue
    gate; python3 "$HERE/xbench.py" session $b "$OUT/$b-$r" > "$OUT/$b-$r.log" 2>&1
    # Up to three tries: now and then the bar takes Return before it has caught up with the URL and opens a search.
    for try in 1 2 3; do
      [ -f "$OUT/sp-$b-$r/result.json" ] && grep -q speedometer "$OUT/sp-$b-$r/result.json" && break
      rm -rf "$OUT/sp-$b-$r"
      gate; python3 "$HERE/xbench.py" speedometer $b "$OUT/sp-$b-$r" > "$OUT/sp-$b-$r.log" 2>&1
    done
  done
done
echo DONE > $OUT/done
