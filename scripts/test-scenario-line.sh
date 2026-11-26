#!/bin/bash
# scripts/scenario-line.sh: what a scenario line keeps of its comments and #s.
set -u
cd "$(dirname "$0")/.."
source scripts/scenario-line.sh
fails=0 checks=0
keeps() {
  checks=$((checks + 1))
  local got
  if ! got="$(scenario_line "$1")"; then echo "✗ [$1] read as a comment, expected [$2]"; fails=$((fails + 1)); return; fi
  [ "$got" = "$2" ] || { echo "✗ [$1] → [$got], expected [$2]"; fails=$((fails + 1)); }
}
comment() {
  checks=$((checks + 1))
  scenario_line "$1" >/dev/null && { echo "✗ [$1] should be a comment"; fails=$((fails + 1)); }
}
comment "# promise: #457"
comment "   # indented"
keeps "budget rss=600 stalls50=10   # each new tab stalls ~100 ms" "budget rss=600 stalls50=10"
keeps "cra://action/renameTab   # from a pane, the split's name" "cra://action/renameTab"
keeps "wait 1 #" "wait 1"
keeps "wait 2   " "wait 2"
# A colour, a regex after #, a fragment: the whole check stays (they were cut at the #).
keeps "expect-log command bar scope enter: YouTube, fill #(4B2323|F6DFDF)" "expect-log command bar scope enter: YouTube, fill #(4B2323|F6DFDF)"
keeps "expect-log boost pick copied #second\$" "expect-log boost pick copied #second\$"
keeps "expect-log panel #1A1A1A at 0\\.85" "expect-log panel #1A1A1A at 0\\.85"
keeps "cra://open?url=\${PAGE}#section" "cra://open?url=\${PAGE}#section"
keeps "expect-log strip #FFFFFF   # white on a light Mac" "expect-log strip #FFFFFF"
[ "$fails" -eq 0 ] && echo "Scenario lines: $checks checks passed" || { echo "Scenario lines: $fails of $checks failed"; exit 1; }
