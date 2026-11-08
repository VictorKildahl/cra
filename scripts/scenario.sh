#!/bin/bash
# Drives the real Cra.app through a user journey (Tests/Scenarios/<name>.scenario) on a
# throwaway profile, behind your other windows, then checks the same invariants for every
# scenario: still running, no new crash report, no fault in cra.log, the sidebar sound,
# main-thread stalls and memory inside the scenario's budget, helper processes back to
# baseline after tabs close, and a clean quit. Never asserts on pixels.
#
#   scripts/scenario.sh fifty-tabs        one scenario
#   scripts/scenario.sh all               every scenario, one after another
#
# CRA_APP (default build/Cra.app) picks the build; CRA_FLAGS (FeatureFlags) is passed on, so
# CRA_FLAGS=backdrop=material runs the NSVisualEffectView path. Scenarios marked
# "requires screen" (they take over a Space) run only with CRA_SCENARIO_SCREEN=1, as in CI.
# CRA_BUDGETS=report (the nightly on GitHub's runners) prints budgets and snapshot differences
# without failing on them: they were set on a Mac, and a runner VM's numbers differ. What the app
# does (expect-log, faults, crashes, helpers, quitting) fails everywhere.
# Logs land in build/scenarios/<name>/.
#
# Scenario lines: a cra:// command (sent through CRA_COMMAND_FILE, then `pace` seconds),
# or one of
#   wait <s>                    let the app work
#   pace <s>                    pause after each command (default 0.2)
#   repeat <n> <cra://…${i}…>   the command n times, ${i} = 1…n
#   budget rss=<MB> maxstall=<ms> stalls50=<n> launchstall=<ms> perfcpu=<% of a core>
#     (stalls count from the first command; start-up has its own launchstall budget)
#   helpers baseline | helpers settle [slack]
#   relaunch                    cra://debug?relaunch=1, then follow the new process
#   expect-log <regex>          a line Cra logged (cra.log or stdout)
#   reject-log <regex>          no such line logged so far
#   snapshot <View[,n]> <name>  the nth visible view of that class drawn to PNG and compared with
#                               Tests/Snapshots/<name>.png (CRA_SNAPSHOT_RECORD=1 records it)
#   fresh                       no seeded settings: onboarding shows, as on a new Mac
#   seed <file> <json>          that data-folder file before launch (a seeded settings.json
#                               replaces the default one)
#   env <NAME=value>            passed to Cra
#   arg <--switch=value>        on Cra's command line, for Chromium (the first launch only: a
#                               relaunch drops it)
#   extension <folder>          copied into the data folder's Extensions/ before launch, as an
#                               import leaves an extension
#   home                        a throwaway home folder, so downloads stay out of ~/Downloads
#   requires screen
#   port <n>                    serve ${PAGE} on a fixed port (snapshots show the address)
# ${FIXTURES}, ${PAGE} (Tests/Fixtures/Pages/page.html from a local server, so it has a host
# for developer mode and tab sleep), ${WEBKIT} (that server as http://localhost:<port>, a host the
# run treats as a DRM service, so its pages open in WebKit), ${EXTENSION_ID} (Tests/Fixtures/Extension) and
# ${SIDE_PANEL_EXTENSION_ID} (Tests/Fixtures/SidePanelExtension) and ${DOWNLOAD_EXTENSION_ID}
# (Tests/Fixtures/DownloadExtension) and ${WEB_STORE_COPY_ID} (Tests/Fixtures/WebStoreCopy) expand,
# and ${STALL}, an address on 127.0.0.1 that takes connections and never answers (a download
# that never ends).
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="${CRA_APP:-$ROOT/build/Cra.app}"
FIXTURES="$ROOT/Tests/Fixtures"
EXTENSION_ID="$(cat "$FIXTURES/Extension/ID")"
SIDE_PANEL_EXTENSION_ID="$(cat "$FIXTURES/SidePanelExtension/ID")"
DOWNLOAD_EXTENSION_ID="$(cat "$FIXTURES/DownloadExtension/ID")"
WEB_STORE_COPY_ID="$(cat "$FIXTURES/WebStoreCopy/ID")"

if [ "${1:-}" = "all" ]; then
  failed=()
  for f in Tests/Scenarios/*.scenario; do
    name="$(basename "$f" .scenario)"
    "$0" "$name" || failed+=("$name")
  done
  [ ${#failed[@]} -eq 0 ] && { echo "All scenarios passed"; exit 0; }
  echo "Failed: ${failed[*]}"; exit 1
fi

NAME="${1:?usage: scripts/scenario.sh <name>|all}"
FILE="Tests/Scenarios/$NAME.scenario"
[ -f "$FILE" ] || { echo "No scenario $FILE"; exit 2; }
[ -x "$APP/Contents/MacOS/Cra" ] || { echo "No Cra at $APP (scripts/build.sh; budgets are a release build's)"; exit 2; }
if grep -q '^requires screen' "$FILE" && [ "${CRA_SCENARIO_SCREEN:-}" != "1" ]; then
  echo "$NAME: skipped (takes over the screen; CRA_SCENARIO_SCREEN=1 runs it)"; exit 0
fi

OUT="$ROOT/build/scenarios/$NAME${CRA_FLAGS:+-${CRA_FLAGS//[^a-z]/}}"
rm -rf "$OUT" && mkdir -p "$OUT"
# The physical path: /tmp is a link to /private/tmp, and CEF takes a profile's folder for one
# outside root_cache_path through it (in-memory storage instead), so spaces on a profile need it.
DATA="$(cd "$(mktemp -d /tmp/cra-scenario.XXXXXX)" && pwd -P)"
CMD="$OUT/commands"
HITCH="$OUT/hitch.log"
LOG="$DATA/cra.log"
: > "$CMD"
STARTED="$OUT/started"
touch "$STARTED"
# The scenario's own data files, environment and home folder.
app_env=(env)
while read -r _ seed json; do echo "$json" > "$DATA/$seed"; done < <(grep '^seed ' "$FILE")
while read -r _ kv; do app_env+=("$kv"); done < <(grep '^env ' "$FILE")
if grep -q '^home$' "$FILE"; then
  mkdir -p "$DATA/home/Downloads"
  app_env+=(CFFIXED_USER_HOME="$DATA/home")
fi
# Past onboarding, and nothing taken from this Mac's Arc (its toolbar default) unless asked.
if ! grep -q '^fresh' "$FILE" && [ ! -f "$DATA/settings.json" ]; then
  echo '{"hasSeenImportPrompt": true, "toolbarDefaultMigrated": true, "showToolbar": false}' > "$DATA/settings.json"
fi

PIDS=()
PID=""
FAULTS=0
LOG_OFFSET=0
PROBLEMS=()
problem() { PROBLEMS+=("$1"); echo "  ✗ $1"; }
NOTES=()
# A budget or a snapshot: a failure, or only a note under CRA_BUDGETS=report.
budget_problem() {
  if [ "${CRA_BUDGETS:-}" = "report" ]; then NOTES+=("$1"); echo "  ⚠ $1"; else problem "$1"; fi
}

# The fixture pages over http on a free port: a real host, no network.
FIXED_PORT=$(sed -n 's/^port \([0-9]*\).*/\1/p' "$FILE" | head -1)
# Not `python3 -m http.server`: it looks up 127.0.0.1's name before it says its port, and on a CI
# runner that lookup outlasted the wait for every scenario after the first (nightly, 3–6 Nov).
python3 -I -u -c '
import functools, http.server, socketserver, sys
class Server(http.server.ThreadingHTTPServer):
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = "127.0.0.1", self.server_address[1]
s = Server(("127.0.0.1", int(sys.argv[2])), functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1]))
print(f"Serving HTTP on 127.0.0.1 port {s.server_address[1]}", flush=True)
s.serve_forever()' "$FIXTURES/Pages" "${FIXED_PORT:-0}" >"$OUT/server.log" 2>&1 &
SERVER=$!
disown "$SERVER"  # killed at the end without a "Terminated" line
for _ in $(seq 1 300); do PORT=$(sed -n 's/.*port \([0-9]*\).*/\1/p' "$OUT/server.log" | head -1); [ -n "$PORT" ] && break; sleep 0.1; done
PAGE="http://127.0.0.1:${PORT:?http server did not start}/page.html"
# The same server under another host, which the run lists as a DRM service (CRA_WEBKIT_HOSTS):
# its pages open in WebKit, the way Spotify and Netflix do (ProtectedMediaSites).
WEBKIT="http://localhost:${PORT}"
# A port that accepts connections (the kernel's backlog does) and never answers one.
python3 -I -u -c '
import socket, time
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen(64)
print(s.getsockname()[1], flush=True)
time.sleep(86400)' >"$OUT/stall.log" 2>&1 &
STALLER=$!
disown "$STALLER"
for _ in $(seq 1 50); do STALL_PORT=$(head -1 "$OUT/stall.log"); [ -n "$STALL_PORT" ] && break; sleep 0.1; done
STALL="http://127.0.0.1:${STALL_PORT:?stalling port did not open}"
expand() { local s="$1"; s="${s//\$\{FIXTURES\}/$FIXTURES}"; s="${s//\$\{PAGE\}/$PAGE}"; s="${s//\$\{WEBKIT\}/$WEBKIT}"; s="${s//\$\{STALL\}/$STALL}"; s="${s//\$\{EXTENSION_ID\}/$EXTENSION_ID}"; s="${s//\$\{SIDE_PANEL_EXTENSION_ID\}/$SIDE_PANEL_EXTENSION_ID}"; s="${s//\$\{DOWNLOAD_EXTENSION_ID\}/$DOWNLOAD_EXTENSION_ID}"; s="${s//\$\{WEB_STORE_COPY_ID\}/$WEB_STORE_COPY_ID}"; printf '%s' "$s"; }
app_args=()
while read -r _ a; do app_args+=("$(expand "$a")"); done < <(grep '^arg ' "$FILE")
while read -r _ f; do mkdir -p "$DATA/Extensions" && cp -R "$(expand "$f")" "$DATA/Extensions/"; done < <(grep '^extension ' "$FILE")

CRA_DATA_DIR="$DATA" CRA_COMMAND_FILE="$CMD" CRA_HITCH_LOG="$HITCH" CRA_TEST_BACKGROUND=1 CRA_WEBKIT_HOSTS=localhost \
  CRA_ARC_DIR="$FIXTURES/Arc" CRA_FLAGS="${CRA_FLAGS:-}" \
  "${app_env[@]}" "$APP/Contents/MacOS/Cra" ${app_args[@]+"${app_args[@]}"} >"$OUT/stdout.log" 2>&1 &
PID=$!
PIDS+=("$PID")

cleanup() {
  for p in "${PIDS[@]}"; do kill -KILL "$p" 2>/dev/null; done
  kill "$SERVER" "$STALLER" 2>/dev/null
  cp "$DATA"/cra*.log "$OUT/" 2>/dev/null
  rm -rf "$DATA"
}
trap cleanup EXIT

# Faults since the last count; a relaunch that rotated cra.log starts the count over.
count_faults() {
  [ -f "$LOG" ] || return
  local lines; lines=$(wc -l < "$LOG" | tr -d ' ')
  [ "$lines" -lt "$LOG_OFFSET" ] && LOG_OFFSET=0
  FAULTS=$((FAULTS + $(tail -n +$((LOG_OFFSET + 1)) "$LOG" | grep -c ' fault: ')))
  tail -n +$((LOG_OFFSET + 1)) "$LOG" | grep ' fault: ' >> "$OUT/faults.txt"
  LOG_OFFSET=$lines
}
send() { printf '%s\n' "$1" >> "$CMD"; }
helpers() { pgrep -P "$PID" 2>/dev/null | wc -l | tr -d ' '; }
alive() { kill -0 "$PID" 2>/dev/null; }

# Ready once Cra reads the command file (it empties the file when it starts reading).
ready() {
  for _ in $(seq 1 150); do grep -q "pid $1 reads commands" "$DATA"/cra*.log 2>/dev/null && return 0; sleep 0.2; done
  return 1
}
ready "$PID" || problem "Cra did not start reading commands in 30 s"
sleep 2

PACE=0.2
RSS_BUDGET=1500 MAXSTALL=1500 STALLS50=10 LAUNCHSTALL=1000 PERFCPU=0.1
BASELINE=""

echo "$NAME (pid $PID, logs in ${OUT#$ROOT/})"
while IFS= read -r raw || [ -n "$raw" ]; do
  line="$(expand "${raw%%#*}")"
  line="${line%"${line##*[![:space:]]}"}"
  [ -z "$line" ] && continue
  alive || { problem "Cra exited during: $line"; break; }
  set -f; set -- $line; set +f
  case "$1" in
    cra://*) send "$line"; sleep "$PACE" ;;
    wait) sleep "$2" ;;
    pace) PACE="$2" ;;
    repeat)
      n="$2"; shift 2; tmpl="$*"
      for i in $(seq 1 "$n"); do send "${tmpl//\$\{i\}/$i}"; sleep "$PACE"; done ;;
    budget)
      shift
      for kv in "$@"; do
        case "$kv" in rss=*) RSS_BUDGET="${kv#*=}" ;; perfcpu=*) PERFCPU="${kv#*=}" ;; launchstall=*) LAUNCHSTALL="${kv#*=}" ;; maxstall=*) MAXSTALL="${kv#*=}" ;; stalls50=*) STALLS50="${kv#*=}" ;; esac
      done ;;
    helpers)
      if [ "$2" = "baseline" ]; then BASELINE=$(helpers); echo "  helpers: baseline $BASELINE"
      else
        slack="${3:-1}"; now=$(helpers)
        for _ in $(seq 1 25); do now=$(helpers); [ "$now" -le $((BASELINE + slack)) ] && break; sleep 0.2; done
        [ "$now" -le $((BASELINE + slack)) ] || problem "helper processes: $now, baseline $BASELINE (+$slack) after 5 s"
      fi ;;
    relaunch)
      count_faults
      # The next Cra starts its hitch log afresh: keep this one's.
      { cat "$HITCH" 2>/dev/null; echo "0 relaunch"; } >> "$OUT/hitch.earlier"
      old="$PID"; send "cra://debug?relaunch=1"
      PID=""
      for _ in $(seq 1 200); do
        p=$(grep -ho 'starts, pid [0-9]*' "$DATA"/cra*.log 2>/dev/null | awk '{print $3}' | grep -vx "$old" | grep -vxF "$(printf '%s\n' "${PIDS[@]}")" | tail -1)
        [ -n "$p" ] && kill -0 "$p" 2>/dev/null && { PID="$p"; break; }
        sleep 0.2
      done
      [ -n "$PID" ] || { problem "no new Cra after relaunch"; PID="$old"; break; }
      PIDS+=("$PID"); echo "  relaunched: pid $PID"
      ready "$PID" || problem "the relaunched Cra did not read commands in 30 s"
      sleep 2 ;;
    expect-log)
      shift; re="$*"; found=""
      for _ in $(seq 1 150); do grep -Eq "$re" "$DATA"/cra*.log "$OUT/stdout.log" 2>/dev/null && { found=1; break; }; sleep 0.2; done
      [ -n "$found" ] || problem "no log line matching: $re" ;;
    reject-log)
      shift; re="$*"
      ! grep -Eq "$re" "$DATA"/cra*.log "$OUT/stdout.log" 2>/dev/null || problem "a log line matching: $re" ;;
    snapshot)
      shot="$OUT/snapshots/$3.png"; ref="$ROOT/Tests/Snapshots/$3.png"
      mkdir -p "$OUT/snapshots"; send "cra://debug?snapshot=$2&out=$shot"
      for _ in $(seq 1 25); do [ -s "$shot" ] && break; sleep 0.2; done
      if [ ! -s "$shot" ]; then problem "no snapshot of $2"
      elif [ "${CRA_SNAPSHOT_RECORD:-}" = "1" ]; then mkdir -p "$ROOT/Tests/Snapshots"; cp "$shot" "$ref"; echo "  recorded $3"
      elif [ ! -f "$ref" ]; then problem "no reference Tests/Snapshots/$3.png (CRA_SNAPSHOT_RECORD=1 records one)"
      else
        [ -x "$OUT/compare-png" ] || xcrun swiftc -O "$ROOT/scripts/compare-png.swift" -o "$OUT/compare-png" 2>"$OUT/compare-png.log"
        verdict=$("$OUT/compare-png" "$ref" "$shot" "$OUT/snapshots/$3.diff.png" 2>&1) || budget_problem "snapshot $3: $verdict"
      fi ;;
    fresh|requires|port|seed|env|arg|extension|home) ;;
    *) problem "unknown scenario line: $line" ;;
  esac
done < "$FILE"

# Invariants.
if alive; then
  send "cra://debug?checkStore=1"; sleep 1
  rss=$(ps -o rss= -p "$PID" | tr -d ' ')
  total=$(( rss + $(ps -o rss= -p "$(pgrep -P "$PID" | paste -sd, -)" 2>/dev/null | awk '{s+=$1} END {print s+0}') ))
  echo "  memory: Cra $((rss / 1024)) MB, with helpers $((total / 1024)) MB (budget $RSS_BUDGET MB for Cra)"
  [ $((rss / 1024)) -le "$RSS_BUDGET" ] || budget_problem "Cra uses $((rss / 1024)) MB, budget $RSS_BUDGET MB"
else
  problem "Cra is not running at the end"
fi
# Stalls after a snapshot command are the snapshot being drawn, not the app.
read -r launch maxstall over50 < <(cat "$OUT/hitch.earlier" "$HITCH" 2>/dev/null | awk '$2 == "relaunch" { started = 0 }
  $2 == "mark" { started = 1; shooting = ($3 ~ /snapshot=/) }
  $2 == "stall" && shooting { next }
  $2 == "stall" && !started { if ($3 > l) l = $3 }
  $2 == "stall" && started { if ($3 > m) m = $3; if ($3 > 50) n++ }
  END { printf "%d %d %d\n", l, m, n }' || echo "0 0 0")
echo "  stalls: start-up ${launch} ms (budget ${LAUNCHSTALL}); then longest ${maxstall} ms, ${over50} over 50 ms (budget ${MAXSTALL} ms, ${STALLS50})"
[ "${launch:-0}" -le "$LAUNCHSTALL" ] || budget_problem "a ${launch} ms main-thread stall at start-up, budget ${LAUNCHSTALL} ms"
[ "${maxstall:-0}" -le "$MAXSTALL" ] || budget_problem "a ${maxstall} ms main-thread stall, budget ${MAXSTALL} ms"
[ "${over50:-0}" -le "$STALLS50" ] || budget_problem "${over50} stalls over 50 ms, budget ${STALLS50}"

# The performance recorder (#91): what it costs, and whether it saw the stalls HitchMonitor saw.
if alive; then
  send "cra://debug?perfReport=$OUT/perf.json"
  for _ in $(seq 1 25); do [ -s "$OUT/perf.json" ] && break; sleep 0.2; done
  hitch250=$(cat "$OUT/hitch.earlier" "$HITCH" 2>/dev/null | awk '$2 == "stall" && $3 >= 250 { n++ } END { print n + 0 }')
  if [ ! -s "$OUT/perf.json" ]; then problem "no perf.json from the performance recorder"
  else
    verdict=$(python3 -I - "$OUT/perf.json" "$PERFCPU" "$hitch250" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
cpu, budget, hitch = r["selfCost"]["cpuPct"], float(sys.argv[2]), int(sys.argv[3])
m = r["mainThread"]
seen = m["freezes"] + m["outsideFreezes"]
print(f"perf: recording costs {cpu:.3f} % of a core (budget {budget}); stalls ≥250 ms: recorder {seen}, HitchMonitor {hitch}")
if cpu > budget: print(f"PROBLEM the performance recorder costs {cpu:.3f} % of a core, budget {budget} %")
# This run's HitchMonitor log starts after the launch the recorder also saw; a few either way is timing.
if abs(seen - hitch) > max(2, hitch // 5): print(f"PROBLEM the recorder counted {seen} stalls of 250 ms or more, HitchMonitor {hitch}")
PY
)
    echo "  $(head -1 <<< "$verdict")"
    while IFS= read -r l; do [[ "$l" == PROBLEM* ]] && budget_problem "${l#PROBLEM }"; done <<< "$verdict"
  fi
fi

# A clean quit, within the CefShutdown watchdog.
if alive; then
  send "cra://debug?quit=1"
  for _ in $(seq 1 100); do alive || break; sleep 0.2; done
  alive && problem "Cra did not quit within 20 s"
fi
# How the Cra this script started ended: a crash on the way out (#227) shows here at once, while
# ReportCrash can take longer than the wait below to write its report. A relaunched Cra isn't
# this shell's child; its crash shows only as a report.
if [ "$PID" = "${PIDS[0]}" ] && ! alive; then
  wait "$PID" 2>/dev/null; status=$?
  [ "$status" -gt 128 ] && problem "Cra ended on signal $((status - 128)) (a crash; while quitting unless reported above)"
fi
count_faults
[ "$FAULTS" -eq 0 ] || problem "$FAULTS fault line(s) in cra.log (faults.txt)"

# Crash reports written for any of this run's processes (ReportCrash needs a moment).
sleep 3
for f in $(find "$HOME/Library/Logs/DiagnosticReports" -name '*.ips' -newer "$STARTED" 2>/dev/null); do
  for p in "${PIDS[@]}"; do
    if grep -Eq "\"(pid|parentPid)\" *: *$p[^0-9]" "$f"; then
      problem "crash report $(basename "$f")"; cp "$f" "$OUT/"; break
    fi
  done
done

result="passed"; [ ${#PROBLEMS[@]} -eq 0 ] || result="FAILED"
echo "$NAME: $result"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "| $NAME${CRA_FLAGS:+ ($CRA_FLAGS)} | $result | ${maxstall:-?} ms / ${over50:-?} | ${rss:+$((rss / 1024)) MB} | ${PROBLEMS[*]:-} ${NOTES[*]:+(over budget: ${NOTES[*]})} |" >> "$GITHUB_STEP_SUMMARY"
fi
[ ${#PROBLEMS[@]} -eq 0 ]
