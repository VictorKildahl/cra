#!/bin/bash
# speedometer.sh [browser...]: Speedometer 3.1 only, the browsers one after another in each of three rounds
# (default: cra craold helium chrome), so every score comes from the same hour. A Mac's Speedometer scores drift
# with the time of day and its temperature; scores from different hours don't compare well.
# Results in $XBENCH_OUT (default $XBENCH_DIR/results-speedometer), one line per run in scores.txt.
B="${XBENCH_DIR:-$HOME/CraBench}"; HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$B"
OUT="${XBENCH_OUT:-$B/results-speedometer}"; mkdir -p "$OUT"
NAMES=("$@"); [ ${#NAMES[@]} -gt 0 ] || NAMES=(cra craold helium chrome)
idle() { ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'; }
gate() { sleep 35; for i in $(seq 1 2000); do [ "$(idle)" -ge 30 ] && return; sleep 10; done; }
for r in 1 2 3; do
  for b in "${NAMES[@]}"; do
    d="$OUT/sp-$b-$r"
    for try in 1 2 3; do
      [ -f "$d/result.json" ] && grep -q speedometer "$d/result.json" && break
      rm -rf "$d"
      gate; python3 "$HERE/xbench.py" speedometer $b "$d" > "$d.log" 2>&1
    done
    echo "$b $r $(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('speedometer'))" "$d/result.json" 2>/dev/null) $(date +%H:%M)" >> "$OUT/scores.txt"
  done
done
echo DONE > "$OUT/done"
