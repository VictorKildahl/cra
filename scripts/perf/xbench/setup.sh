#!/bin/bash
# setup.sh: the bench folder ($XBENCH_DIR, default ~/CraBench): tools, pages, Speedometer 3.1 with the score hook,
# and the offline profile. Then: copy a signed Cra build to $XBENCH_DIR/Cra.app and Helium's to Helium.app, run
# prep.sh for Arc and Dia, and `xbench.py warm <browser>` once for each of cra helium arc dia.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; B="${XBENCH_DIR:-$HOME/CraBench}"
mkdir -p "$B/tools" "$B/pages"
for t in wins waitwin key front axset axget; do swiftc -O "$HERE/tools/$t.swift" -o "$B/tools/$t"; done
# fp: CPU time, wakeups and phys_footprint summed over a process tree (xbench.py reads it from build/perf).
mkdir -p "$HERE/../../../build/perf"; xcrun swiftc -O "$HERE/../fp.swift" -o "$HERE/../../../build/perf/fp"
cp "$HERE/offline.sb" "$B/"; cp "$HERE/pages/bench.html" "$B/pages/"
if [ ! -d "$B/pages/speedometer" ]; then
  git clone -q --depth 1 -b release/3.1 https://github.com/WebKit/Speedometer.git "$B/pages/speedometer"
fi
cp "$HERE/pages/cra-bench-hook.js" "$B/pages/speedometer/"
grep -q cra-bench-hook "$B/pages/speedometer/index.html" ||
  sed -i '' 's|</head>|<script src="cra-bench-hook.js"></script></head>|' "$B/pages/speedometer/index.html"
echo "set up $B"
