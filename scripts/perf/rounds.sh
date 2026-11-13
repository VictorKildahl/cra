#!/bin/bash
# Interleaved bench runs of several builds, the order rotated each round, so they see the same Mac.
#   scripts/perf/rounds.sh <out dir> <rounds> <name>=<app> [<name>=<app> ...]
#   e.g. caffeinate -d scripts/perf/rounds.sh build/perf/gate 3 before=/tmp/before/Cra.app after=build/Cra.app
# Then: python3 scripts/perf/report.py <out dir>/*-[0-9]*
B="$(cd "$(dirname "$0")" && pwd)"; OUT="$1"; N="$2"; shift 2
for r in $(seq 1 "$N"); do
  set -- "${@:2}" "$1"
  for spec in "$@"; do "$B/bench.sh" "${spec#*=}" "$OUT/${spec%%=*}-$r"; done
done
echo "rounds done: $OUT"
