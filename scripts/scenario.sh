#!/bin/bash
# Drives the real Cra.app through a user journey (Tests/Scenarios/<name>.scenario) on a
# throwaway profile, behind your other windows, then checks the same invariants for every
# scenario: still running, no new crash report, no page crash ("Aw, Snap!") in the performance
# recorder's report, no fault in cra.log, the sidebar sound,
# main-thread stalls and memory inside the scenario's budget, helper processes back to
# baseline after tabs close, and a clean quit. Never asserts on pixels.
#
#   scripts/scenario.sh fifty-tabs        one scenario
#   scripts/scenario.sh all               every scenario, one after another
#   scripts/scenario.sh web-features      the web features' scenarios (Tests/web-features.tsv), a release's gate
#   scripts/scenario.sh snapshots         every scenario that takes a snapshot, compared strictly on a 2x screen, a release's gate
#
# CRA_APP (default build/Cra.app) picks the build; CRA_FLAGS (FeatureFlags) is passed on, so
# CRA_FLAGS=backdrop=material runs the NSVisualEffectView path. Scenarios marked
# "requires screen" (they take over a Space) run only with CRA_SCENARIO_SCREEN=1, as in CI.
# CRA_BUDGETS=report (the nightly on GitHub's runners) prints budgets and snapshot differences
# without failing on them: they were set on a Mac, and a runner VM's numbers differ. What the app
# does (expect-log, faults, crashes, helpers, quitting) fails everywhere. CRA_SNAPSHOTS=strict fails
# on a snapshot that differs or couldn't be compared (a 1x display) even then: the snapshots gate.
# Logs land in build/scenarios/<name>/.
#
# Scenario lines: a cra:// command (sent through CRA_COMMAND_FILE, then `pace` seconds),
# or one of
#   wait <s>                    let the app work
#   pace <s>                    pause after each command (default 0.2)
#   repeat <n> <cra://…${i}…>   the command n times, ${i} = 1…n
#   budget rss=<MB> maxstall=<ms> stalls50=<n> launchstall=<ms> perfcpu=<% of a core>
#     stalls16=<n> (dropped frames: stalls over 16 ms; no budget unless a scenario sets one)
#     (stalls count from the first command; start-up has its own launchstall budget)
#   helpers baseline | helpers settle [slack]
#   renderers <max>             at most that many renderer processes (within 5 s)
#   relaunch [<cra:// command>] cra://debug?relaunch=1 (or that command, which restarts Cra), then follow the new
#                               process
#   expect-log <regex>          a line Cra logged (cra.log, the engine's chromium.log or stdout), ${WS}'s "ws open" /
#                               "ws closed", or a request the fixture server answered ("GET /page.html?n=1 HTTP/1.1")
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
#   profile <folder>            its contents copied into the data folder before launch: files an
#                               older Cra left (Tests/Fixtures/CEFProfile, Cra on CEF's cookies)
#   home                        a throwaway home folder, so downloads stay out of ~/Downloads
#   crash-report <file>         copied into the throwaway home's Library/Logs/DiagnosticReports
#                               before launch, as macOS leaves one (needs home)
#   cover                       another app's window over the browser window, right above it in the window order
#                               (scripts/cover-window/cover.m); ${COVER} is its pid, for cra://debug?yieldTo=${COVER}
#   cover link                  that app, once in front, brings Cra forward, as for a link clicked in it (#607)
#   click little-close          a real click (through the window server, scripts/hid-click/click.m) on the newest
#                               Little Window's close button, only if that window is in front there; needs a screen
#                               (requires screen), as Cra comes forward for it as for a mouse (#659)
#   click toolbar-empty double  a real double click the same way on the focused page's toolbar where no button is (#685)
#   click page-top double       the same 5 pt into the focused page's top (#685)
#   bare-helper <suffix>        runs the engine's "Cra Helper (<suffix>)" with no arguments, as macOS launches the
#                               Alerts helper for a notification click after it quit; fails unless it exits 0 in 10 s
#   replace-app [chrome]        Cra.app replaced while Cra runs, as `brew upgrade --greedy` does: a scenario with this
#                               line runs its own copy of the app (an APFS clone in its output folder), which goes,
#                               and a copy of it one version on takes its place; with `chrome`, that copy's engine
#                               is on another Chrome too (Versions/<chrome> moved), so new pages can't start (the
#                               recorder's "launch failed" then counts as no crash)
#   requires screen
#   port <n>                   serve ${PAGE} on a fixed port (snapshots show the address)
# The fixture server answers an address with ?delay=<s> (or &delay=<s>) that many seconds late, and /auth with an
# HTTP sign-in (401 Basic) until the browser sends a user name and password.
# ${FIXTURES}, ${ORIGIN} (that server's http://127.0.0.1:<port>, which also answers a POST with 204,
# logs it to server.log and keeps its body in posts/), ${PAGE} (Tests/Fixtures/Pages/page.html from a local server, so it has a host
# for developer mode and tab sleep), ${WEBKIT} (that server as http://localhost:<port>, a host the
# run treats as a DRM service, so its pages open in WebKit), ${MUSIC} (that server as
# http://nts.live:<port>, a recognized music host, for a scenario whose `arg` maps the name to
# 127.0.0.1), ${EXTENSION_ID} (Tests/Fixtures/Extension) and
# ${WS}, a WebSocket server on 127.0.0.1 that keeps every connection open (ws://127.0.0.1:<port>), and
# ${SIDE_PANEL_EXTENSION_ID} (Tests/Fixtures/SidePanelExtension) and ${DOWNLOAD_EXTENSION_ID}
# (Tests/Fixtures/DownloadExtension) and ${WEB_STORE_COPY_ID} (Tests/Fixtures/WebStoreCopy) and
# ${TABS_CREATE_EXTENSION_ID} (Tests/Fixtures/TabsCreateExtension) and ${TABS_QUERY_EXTENSION_ID}
# (Tests/Fixtures/TabsQueryExtension) and ${CAPTURE_EXTENSION_ID} (Tests/Fixtures/CaptureExtension) and
# ${POPUP_CONTEXT_EXTENSION_ID} (Tests/Fixtures/PopupContextExtension) and ${COMMANDS_EXTENSION_ID}
# (Tests/Fixtures/CommandsExtension) expand,
# and ${STALL}, an address on 127.0.0.1 that takes connections and never answers (a download
# that never ends), and ${TRICKLE}, one that answers with a 10 MB file to save, sends the first
# 64 KB and holds the rest back (a download that stays in progress).
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="${CRA_APP:-$ROOT/build/Cra.app}"
FIXTURES="$ROOT/Tests/Fixtures"
EXTENSION_ID="$(cat "$FIXTURES/Extension/ID")"
SIDE_PANEL_EXTENSION_ID="$(cat "$FIXTURES/SidePanelExtension/ID")"
DOWNLOAD_EXTENSION_ID="$(cat "$FIXTURES/DownloadExtension/ID")"
WEB_STORE_COPY_ID="$(cat "$FIXTURES/WebStoreCopy/ID")"
# A Chrome Web Store extension's folder copy, as Cra imports one (#660).
STORE_COPY_EXTENSION_ID="$(cat "$FIXTURES/StoreCopyExtension/ID")"
TABS_CREATE_EXTENSION_ID="$(cat "$FIXTURES/TabsCreateExtension/ID")"
TABS_QUERY_EXTENSION_ID="$(cat "$FIXTURES/TabsQueryExtension/ID")"
CAPTURE_EXTENSION_ID="$(cat "$FIXTURES/CaptureExtension/ID")"
POPUP_CONTEXT_EXTENSION_ID="$(cat "$FIXTURES/PopupContextExtension/ID")"
COMMANDS_EXTENSION_ID="$(cat "$FIXTURES/CommandsExtension/ID")"

if [ "${1:-}" = "all" ]; then
  # CRA_SCENARIO_SHARD=k/n runs every n-th scenario from the k-th (1-based), so n jobs share the list: one job
  # ran out of Nightly's hour after 118 of 321, and the rest never ran.
  shard="${CRA_SCENARIO_SHARD:-1/1}"
  k="${shard%/*}"; n="${shard#*/}"
  [[ "$k" =~ ^[0-9]+$ && "$n" =~ ^[0-9]+$ && "$k" -ge 1 && "$k" -le "$n" ]] || { echo "CRA_SCENARIO_SHARD is k/n, 1 <= k <= n: $shard" >&2; exit 2; }
  failed=()
  i=0
  for f in Tests/Scenarios/*.scenario; do
    i=$((i + 1))
    [ $(((i - 1) % n)) -eq $((k - 1)) ] || continue
    name="$(basename "$f" .scenario)"
    "$0" "$name" || failed+=("$name")
  done
  [ ${#failed[@]} -eq 0 ] && { echo "All scenarios passed"; exit 0; }
  echo "Failed: ${failed[*]}"; exit 1
fi

# web-features: every scenario Tests/web-features.tsv names (docs/web-features.md), what scripts/release.sh runs on
# a release's build. Those that run without the screen go CRA_LANES at a time (default 3), the screen ones one by
# one after them (CRA_SCENARIO_SCREEN=1). build/scenarios/web-features.txt says how it went, with the engine.
if [ "${1:-}" = "web-features" ]; then
  names=$(python3 -I scripts/web-features.py --scenarios) || exit 2
  mkdir -p build/scenarios
  REPORT=build/scenarios/web-features.txt
  RESULTS="$(mktemp /tmp/cra-web-features.XXXXXX)"
  quiet=() screen=()
  for n in $names; do
    if grep -q '^requires screen' "Tests/Scenarios/$n.scenario"; then screen+=("$n"); else quiet+=("$n"); fi
  done
  run_one() { "$1" "$2" > "build/scenarios/$2.out" 2>&1; echo "$2 $?" >> "$3"; }
  export -f run_one
  printf '%s\n' ${quiet[@]+"${quiet[@]}"} | xargs -P "${CRA_LANES:-3}" -I{} bash -c 'run_one "$0" "$1" "$2"' "$0" {} "$RESULTS"
  for n in ${screen[@]+"${screen[@]}"}; do run_one "$0" "$n" "$RESULTS"; done
  failed=() skipped=() passed=()
  while read -r n code; do
    if [ "$code" != 0 ]; then failed+=("$n")
    elif grep -q ': skipped' "build/scenarios/$n.out"; then skipped+=("$n")
    else passed+=("$n"); fi
  done < "$RESULTS"
  rm -f "$RESULTS"
  APP_FOR_REPORT="${CRA_APP:-$ROOT/build/Cra.app}"
  {
    echo "web features on $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_FOR_REPORT/Contents/Info.plist" 2>/dev/null || echo '?')" \
         "($(cat "$APP_FOR_REPORT/Contents/Frameworks/Cra Framework.framework/Versions/Current/Resources/Info.plist" 2>/dev/null | plutil -extract CFBundleShortVersionString raw - 2>/dev/null || echo 'engine ?'), $(uname -m))"
    echo "passed ${#passed[@]}, skipped ${#skipped[@]} (they take the screen), failed ${#failed[@]}"
    [ ${#failed[@]} -eq 0 ] || echo "failed: ${failed[*]}"
    [ ${#skipped[@]} -eq 0 ] || echo "skipped: ${skipped[*]}"
    [ ${#failed[@]} -eq 0 ] && echo "result: passed" || echo "result: failed"
  } > "$REPORT"
  cat "$REPORT"
  for n in ${failed[@]+"${failed[@]}"}; do echo "--- $n"; grep -E '✗' "build/scenarios/$n.out"; done
  [ ${#failed[@]} -eq 0 ]
  exit
fi

# snapshots: every scenario with a snapshot line, one at a time (some serve their pages on a fixed port), with
# CRA_SNAPSHOTS=strict and CRA_BUDGETS=report: a snapshot that differs from Tests/Snapshots, or couldn't be compared,
# fails; budgets are only noted. References are 2x, so the copies open on a 2x display: CRA_TEST_SCREEN when it
# names one, else the first one connected, else the virtual 2x "Cra Test Display" (scripts/test-display.sh), taken
# away afterwards. What scripts/release.sh runs after the web features: component-snapshots broke on main when
# PR #678 gave the Arc fixture its icons (22 Nov 2026), and nothing ran it. build/scenarios/snapshots.txt says how it went.
if [ "${1:-}" = "snapshots" ]; then
  mkdir -p build/scenarios
  REPORT=build/scenarios/snapshots.txt
  xcrun swiftc -O scripts/retina-screen.swift -o build/scenarios/retina-screen 2>/dev/null || { echo "snapshots: can't build scripts/retina-screen.swift"; exit 2; }
  screens="$(build/scenarios/retina-screen)"
  VDISPLAY=""
  if [ -n "${CRA_TEST_SCREEN:-}" ] && grep -qiF -- "$CRA_TEST_SCREEN" <<< "$screens"; then SCREEN="$CRA_TEST_SCREEN"
  elif [ -n "$screens" ]; then SCREEN="$(head -1 <<< "$screens")"
  else
    scripts/test-display.sh >/dev/null || { echo "snapshots: no 2x display, and macOS wouldn't make the virtual one"; exit 2; }
    VDISPLAY="$(cat build/vdisplay.pid)"; SCREEN="Cra Test Display"
    trap 'kill "$VDISPLAY" 2>/dev/null' EXIT
  fi
  # A failure runs once more: sidebar-parity's dark tiles drew a pixel apart once in about ten runs (22 Nov 2026),
  # where a real change (a fixture's new icons) fails every time. One that passed only the second time is listed.
  failed=() passed=() flaky=()
  one() { CRA_TEST_SCREEN="$SCREEN" CRA_SNAPSHOTS=strict CRA_BUDGETS=report "$0" "$1" > "build/scenarios/$1.out" 2>&1; }
  for f in $(grep -l '^snapshot ' Tests/Scenarios/*.scenario); do
    n="$(basename "$f" .scenario)"
    if one "$n"; then passed+=("$n")
    else
      cp "build/scenarios/$n.out" "build/scenarios/$n.first.out"
      if one "$n"; then passed+=("$n"); flaky+=("$n"); else failed+=("$n"); fi
    fi
  done
  APP_FOR_REPORT="${CRA_APP:-$ROOT/build/Cra.app}"
  {
    echo "snapshots on $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_FOR_REPORT/Contents/Info.plist" 2>/dev/null || echo '?')" \
         "($(uname -m), on \"$SCREEN\"$([ -n "$VDISPLAY" ] && echo ', virtual'))"
    echo "passed ${#passed[@]}, failed ${#failed[@]}"
    [ ${#failed[@]} -eq 0 ] || echo "failed: ${failed[*]}"
    [ ${#flaky[@]} -eq 0 ] || echo "passed only the second time: ${flaky[*]}"
    [ ${#failed[@]} -eq 0 ] && echo "result: passed" || echo "result: failed"
  } > "$REPORT"
  cat "$REPORT"
  for n in ${failed[@]+"${failed[@]}"}; do echo "--- $n"; grep -E '✗' "build/scenarios/$n.out"; done
  for n in ${flaky[@]+"${flaky[@]}"}; do echo "--- $n, the first time"; grep -E '✗' "build/scenarios/$n.first.out"; done
  [ ${#failed[@]} -eq 0 ]
  exit
fi

NAME="${1:?usage: scripts/scenario.sh <name>|all|web-features|snapshots}"
FILE="Tests/Scenarios/$NAME.scenario"
[ -f "$FILE" ] || { echo "No scenario $FILE"; exit 2; }
# The app's executable: Cra, or CraEngine for a build on Chrome's own framework (CRA_ENGINE=chromium).
EXE="$APP/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist" 2>/dev/null || echo Cra)"
[ -x "$EXE" ] || { echo "No Cra at $APP (scripts/build.sh; budgets are a release build's)"; exit 2; }
if grep -q '^requires screen' "$FILE" && [ "${CRA_SCENARIO_SCREEN:-}" != "1" ]; then
  echo "$NAME: skipped (takes over the screen; CRA_SCENARIO_SCREEN=1 runs it)"; exit 0
fi

OUT="$ROOT/build/scenarios/$NAME${CRA_FLAGS:+-${CRA_FLAGS//[^a-z]/}}"
rm -rf "$OUT" && mkdir -p "$OUT"
# replace-app replaces the app it runs, so that is a copy of the build.
if grep -q '^replace-app' "$FILE"; then
  mkdir -p "$OUT/app" && cp -c -R "$APP" "$OUT/app/Cra.app" || { echo "No copy of $APP"; exit 2; }
  APP="$OUT/app/Cra.app"; EXE="$APP/Contents/MacOS/$(basename "$EXE")"
fi
# The physical path: /tmp is a link to /private/tmp, and CEF takes a profile's folder for one
# outside root_cache_path through it (in-memory storage instead), so spaces on a profile need it.
# CRA_SCENARIO_DATA keeps the data folder for the next scenario (scripts/engine-migration.sh).
if [ -n "${CRA_SCENARIO_DATA:-}" ]; then
  mkdir -p "$CRA_SCENARIO_DATA" && DATA="$(cd "$CRA_SCENARIO_DATA" && pwd -P)"
else
  DATA="$(cd "$(mktemp -d /tmp/cra-scenario.XXXXXX)" && pwd -P)"
fi
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
# ${PAGE} is on 127.0.0.1, which starts in Developer Mode as in Arc (#228). Runs start with it
# turned off, as after ⌃D, so pages show the normal bar; a seeded settings.json that names
# disabledDefaultDeveloperHosts keeps its own.
if [ -f "$DATA/settings.json" ]; then
  python3 -I -c '
import json, sys
p = sys.argv[1]; s = json.load(open(p))
s.setdefault("disabledDefaultDeveloperHosts", ["127.0.0.1"])
json.dump(s, open(p, "w"))' "$DATA/settings.json"
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
import functools, http.server, os, socketserver, sys
class Server(http.server.ThreadingHTTPServer):
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = "127.0.0.1", self.server_address[1]
class Handler(http.server.SimpleHTTPRequestHandler):
    # ?delay=<s> anywhere in the address: the answer (a page, or a 404) comes that many seconds late.
    def do_GET(self):
        import base64, html, re, time
        # /auth: a page behind a user name and password (HTTP Basic), as a router or an intranet asks for one:
        # 401 until the browser sends credentials, then a page titled with the user it signed in as.
        if self.path.startswith("/auth"):
            sent = self.headers.get("Authorization", "")
            if not sent.startswith("Basic "):
                self.send_response(401)
                self.send_header("WWW-Authenticate", "Basic realm=\"Cra fixture\"")
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(b"<title>needs sign-in</title>401")
                return
            user = base64.b64decode(sent[6:]).decode("utf-8", "replace").split(":", 1)[0]
            body = f"<title>signed in as {html.escape(user)}</title>ok".encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        m = re.search(r"[?&]delay=([0-9.]+)", self.path)
        if m:
            time.sleep(float(m.group(1)))
            self.path = self.path.split("?", 1)[0]
        super().do_GET()
    # Settings ▸ Privacy sharing posts here under CRA_SHARING_ENDPOINT=${ORIGIN}.
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        kind = self.headers.get("Content-Type")
        # The install check-in is three short fields: logged whole, so a scenario can expect its id.
        shown = " " + " ".join(body.decode("utf-8", "replace").split()) if self.path.endswith("/checkin") else ""
        print(f"POST {self.path} {len(body)} bytes {kind}{shown}", flush=True)
        # /echo: a form that posts and gets a page back (an order, a search), the page a reload asks about.
        if self.path.startswith("/echo"):
            text = body.decode("utf-8", "replace")
            page = f"<title>posted {len(body)} bytes</title>{text}".encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", str(len(page)))
            self.end_headers()
            self.wfile.write(page)
            return
        os.makedirs(sys.argv[3], exist_ok=True)
        name = self.path.strip("/").replace("/", "-")
        open(os.path.join(sys.argv[3], f"{name}-{len(os.listdir(sys.argv[3])) + 1}.json"), "wb").write(body)
        self.send_response(204)
        self.end_headers()
s = Server(("127.0.0.1", int(sys.argv[2])), functools.partial(Handler, directory=sys.argv[1]))
print(f"Serving HTTP on 127.0.0.1 port {s.server_address[1]}", flush=True)
s.serve_forever()' "$FIXTURES/Pages" "${FIXED_PORT:-0}" "$OUT/posts" >"$OUT/server.log" 2>&1 &
SERVER=$!
disown "$SERVER"  # killed at the end without a "Terminated" line
for _ in $(seq 1 300); do PORT=$(sed -n 's/.*port \([0-9]*\).*/\1/p' "$OUT/server.log" | head -1); [ -n "$PORT" ] && break; sleep 0.1; done
PAGE="http://127.0.0.1:${PORT:?http server did not start}/page.html"
ORIGIN="http://127.0.0.1:$PORT"
# The same server under another host, which the run lists as a DRM service (CRA_WEBKIT_HOSTS):
# its pages open in WebKit, the way Spotify and Netflix do (ProtectedMediaSites).
WEBKIT="http://localhost:${PORT}"
# A music host recognized by MusicNotes, mapped to this Mac by the scenario:
#   arg --host-resolver-rules=MAP nts.live 127.0.0.1
MUSIC="http://nts.live:${PORT}"
# A name on the user's own network (#625), mapped to this Mac by the scenario:
#   arg --host-resolver-rules=MAP nas.local 127.0.0.1
LOCALNET="http://nas.local:${PORT}"
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
python3 -I -u -c '
import socket, threading, time
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0))
s.listen(16)
print(s.getsockname()[1], flush=True)
held = []
def serve(c):
    try:
        c.recv(65536)
        c.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: 10000000\r\n"
                  b"Content-Disposition: attachment; filename=\"trickle.bin\"\r\n\r\n" + b"\0" * 65536)
        held.append(c)
    except OSError:
        c.close()
while True:
    c, _ = s.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()' >"$OUT/trickle.log" 2>&1 &
TRICKLER=$!
disown "$TRICKLER"
for _ in $(seq 1 50); do TRICKLE_PORT=$(head -1 "$OUT/trickle.log"); [ -n "$TRICKLE_PORT" ] && break; sleep 0.1; done
TRICKLE="http://127.0.0.1:${TRICKLE_PORT:?trickle port did not open}"
# A WebSocket server that answers the handshake and holds the connection, logging opens and closes.
python3 -I -u -c '
import base64, hashlib, socket, threading
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0))
s.listen(16)
print(s.getsockname()[1], flush=True)
def serve(c):
    try:
        req = c.recv(65536).decode("latin-1")
        key = next(l.split(":", 1)[1].strip() for l in req.split("\r\n") if l.lower().startswith("sec-websocket-key:"))
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        c.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                   "Sec-WebSocket-Accept: " + accept + "\r\n\r\n").encode())
        print("ws open", flush=True)
        while c.recv(65536):
            pass
    except (OSError, StopIteration):
        pass
    print("ws closed", flush=True)
    c.close()
while True:
    c, _ = s.accept()
    threading.Thread(target=serve, args=(c,), daemon=True).start()' >"$OUT/ws.log" 2>&1 &
WS_SERVER=$!
disown "$WS_SERVER"
for _ in $(seq 1 50); do WS_PORT=$(head -1 "$OUT/ws.log"); [ -n "$WS_PORT" ] && break; sleep 0.1; done
WS="ws://127.0.0.1:${WS_PORT:?WebSocket server did not start}"
expand() { local s="$1"; s="${s//\$\{FIXTURES\}/$FIXTURES}"; s="${s//\$\{ORIGIN\}/$ORIGIN}"; s="${s//\$\{PAGE\}/$PAGE}"; s="${s//\$\{WEBKIT\}/$WEBKIT}"; s="${s//\$\{MUSIC\}/$MUSIC}"; s="${s//\$\{LOCALNET\}/$LOCALNET}"; s="${s//\$\{STALL\}/$STALL}"; s="${s//\$\{TRICKLE\}/$TRICKLE}"; s="${s//\$\{WS\}/$WS}"; s="${s//\$\{COVER\}/${COVER:-}}"; s="${s//\$\{EXTENSION_ID\}/$EXTENSION_ID}"; s="${s//\$\{SIDE_PANEL_EXTENSION_ID\}/$SIDE_PANEL_EXTENSION_ID}"; s="${s//\$\{DOWNLOAD_EXTENSION_ID\}/$DOWNLOAD_EXTENSION_ID}"; s="${s//\$\{WEB_STORE_COPY_ID\}/$WEB_STORE_COPY_ID}"; s="${s//\$\{STORE_COPY_EXTENSION_ID\}/$STORE_COPY_EXTENSION_ID}"; s="${s//\$\{TABS_CREATE_EXTENSION_ID\}/$TABS_CREATE_EXTENSION_ID}"; s="${s//\$\{TABS_QUERY_EXTENSION_ID\}/$TABS_QUERY_EXTENSION_ID}"; s="${s//\$\{CAPTURE_EXTENSION_ID\}/$CAPTURE_EXTENSION_ID}"; s="${s//\$\{POPUP_CONTEXT_EXTENSION_ID\}/$POPUP_CONTEXT_EXTENSION_ID}"; s="${s//\$\{COMMANDS_EXTENSION_ID\}/$COMMANDS_EXTENSION_ID}"; printf '%s' "$s"; }
# AppKit asks "reopen windows?" after a test copy was killed, and that modal blocks every command;
# Cra restores its own windows from windows.json, so AppKit's restoration is off.
app_args=(-ApplePersistenceIgnoreState YES)
while read -r _ a; do app_args+=("$(expand "$a")"); done < <(grep '^arg ' "$FILE")
while read -r _ f; do mkdir -p "$DATA/Extensions" && cp -R "$(expand "$f")" "$DATA/Extensions/"; done < <(grep '^extension ' "$FILE")
while read -r _ f; do cp -R "$(expand "$f")/." "$DATA/"; done < <(grep '^profile ' "$FILE")
while read -r _ f; do mkdir -p "$DATA/home/Library/Logs/DiagnosticReports" && cp "$(expand "$f")" "$DATA/home/Library/Logs/DiagnosticReports/"; done < <(grep '^crash-report ' "$FILE")
for i in "${!app_env[@]}"; do app_env[$i]="$(expand "${app_env[$i]}")"; done

CRA_DATA_DIR="$DATA" CRA_COMMAND_FILE="$CMD" CRA_HITCH_LOG="$HITCH" CRA_TEST_BACKGROUND=1 CRA_WEBKIT_HOSTS=localhost \
  CRA_ARC_DIR="$FIXTURES/Arc" CRA_FLAGS="${CRA_FLAGS:-}" \
  "${app_env[@]}" "$EXE" ${app_args[@]+"${app_args[@]}"} >"$OUT/stdout.log" 2>&1 &
PID=$!
PIDS+=("$PID")

cleanup() {
  for p in "${PIDS[@]}"; do kill -KILL "$p" 2>/dev/null; done
  [ -n "${COVER:-}" ] && kill "$COVER" 2>/dev/null
  kill "$SERVER" "$STALLER" "$TRICKLER" "$WS_SERVER" 2>/dev/null
  cp "$DATA"/cra*.log "$OUT/" 2>/dev/null
  [ -n "${CRA_SCENARIO_DATA:-}" ] || rm -rf "$DATA"
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
# Cra's renderer processes, as Chrome names them on their command lines.
renderers() {
  local n=0 c
  for c in $(pgrep -P "$PID" 2>/dev/null); do ps -ww -o command= -p "$c" | grep -q -- '--type=renderer' && n=$((n + 1)); done
  echo "$n"
}
alive() { kill -0 "$PID" 2>/dev/null; }

# Ready once Cra reads the command file (it empties the file when it starts reading).
ready() {
  for _ in $(seq 1 150); do grep -q "pid $1 reads commands" "$DATA"/cra*.log 2>/dev/null && return 0; sleep 0.2; done
  return 1
}
ready "$PID" || problem "Cra did not start reading commands in 30 s"
sleep 2

PACE=0.2
RSS_BUDGET=1500 MAXSTALL=1500 STALLS50=10 STALLS16= LAUNCHSTALL=1000 PERFCPU=0.1
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
        case "$kv" in rss=*) RSS_BUDGET="${kv#*=}" ;; perfcpu=*) PERFCPU="${kv#*=}" ;; launchstall=*) LAUNCHSTALL="${kv#*=}" ;; maxstall=*) MAXSTALL="${kv#*=}" ;; stalls50=*) STALLS50="${kv#*=}" ;; stalls16=*) STALLS16="${kv#*=}" ;; esac
      done ;;
    helpers)
      if [ "$2" = "baseline" ]; then BASELINE=$(helpers); echo "  helpers: baseline $BASELINE"
      else
        slack="${3:-1}"; now=$(helpers)
        for _ in $(seq 1 25); do now=$(helpers); [ "$now" -le $((BASELINE + slack)) ] && break; sleep 0.2; done
        [ "$now" -le $((BASELINE + slack)) ] || problem "helper processes: $now, baseline $BASELINE (+$slack) after 5 s"
      fi ;;
    renderers)
      now=$(renderers)
      for _ in $(seq 1 25); do now=$(renderers); [ "$now" -le "$2" ] && break; sleep 0.2; done
      echo "  renderers: $now (at most $2)"
      [ "$now" -le "$2" ] || problem "renderer processes: $now, at most $2" ;;
    relaunch)
      count_faults
      # The next Cra starts its hitch log afresh: keep this one's.
      { cat "$HITCH" 2>/dev/null; echo "0 relaunch"; } >> "$OUT/hitch.earlier"
      old="$PID"; send "${2:-cra://debug?relaunch=1}"
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
      # chromium.log has the engine's own LOG lines (bridge hooks and patches; the app's go to stdout.log).
      for _ in $(seq 1 150); do grep -Eq "$re" "$DATA"/cra*.log "$DATA/chromium.log" "$OUT/stdout.log" "$OUT/ws.log" "$OUT/server.log" 2>/dev/null && { found=1; break; }; sleep 0.2; done
      [ -n "$found" ] || problem "no log line matching: $re" ;;
    reject-log)
      shift; re="$*"
      ! grep -Eq "$re" "$DATA"/cra*.log "$OUT/stdout.log" "$OUT/ws.log" "$OUT/server.log" 2>/dev/null || problem "a log line matching: $re" ;;
    snapshot)
      shot="$OUT/snapshots/$3.png"; ref="$ROOT/Tests/Snapshots/$3.png"
      # A name shot twice (before and after a relaunch) must not find the first file and stop waiting.
      shot1x="$OUT/snapshots/$3.1x.png"
      mkdir -p "$OUT/snapshots"; rm -f "$shot" "$shot1x"; send "cra://debug?snapshot=$2&out=$shot"
      for _ in $(seq 1 25); do [ -s "$shot" ] || [ -s "$shot1x" ] && break; sleep 0.2; done
      # References are 2x. On a 1x display (an external monitor, CRA_TEST_SCREEN) text and images
      # are only scaled up, so every one would differ; say that instead, and never record it.
      if [ -s "$shot1x" ]; then
        if [ "${CRA_SNAPSHOT_RECORD:-}" = "1" ]; then problem "snapshot $3: the window is on a 1x display; record on a Retina one"
        elif [ "${CRA_SNAPSHOTS:-}" = "strict" ]; then problem "snapshot $3: not compared, the window is on a 1x display (references are 2x; use a Retina screen)"
        else budget_problem "snapshot $3: not compared, the window is on a 1x display (references are 2x; use a Retina screen)"; fi
      elif [ ! -s "$shot" ]; then problem "no snapshot of $2"
      elif [ "${CRA_SNAPSHOT_RECORD:-}" = "1" ]; then mkdir -p "$ROOT/Tests/Snapshots"; cp "$shot" "$ref"; echo "  recorded $3"
      elif [ ! -f "$ref" ]; then problem "no reference Tests/Snapshots/$3.png (CRA_SNAPSHOT_RECORD=1 records one)"
      else
        [ -x "$OUT/compare-png" ] || xcrun swiftc -O "$ROOT/scripts/compare-png.swift" -o "$OUT/compare-png" 2>"$OUT/compare-png.log"
        if ! verdict=$("$OUT/compare-png" "$ref" "$shot" "$OUT/snapshots/$3.diff.png" 2>&1); then
          if [ "${CRA_SNAPSHOTS:-}" = "strict" ]; then problem "snapshot $3: $verdict"; else budget_problem "snapshot $3: $verdict"; fi
        fi
      fi ;;
    cover)
      if [ "${2:-}" = "link" ]; then
        if [ -n "${COVER:-}" ] && kill -USR1 "$COVER" 2>/dev/null; then sleep 0.3; else problem "cover link: no cover window"; fi
        continue
      fi
      [ -x "$OUT/cover" ] || clang -fobjc-arc -framework AppKit "$ROOT/scripts/cover-window/cover.m" -o "$OUT/cover" 2>"$OUT/cover-build.log"
      if [ ! -x "$OUT/cover" ]; then problem "the cover window did not build (cover-build.log)"
      else
        "$OUT/cover" "$PID" >"$OUT/cover.log" 2>&1 & COVER=$!
        for _ in $(seq 1 50); do grep -q '^covering' "$OUT/cover.log" && break; sleep 0.2; done
        grep -q '^covering' "$OUT/cover.log" && echo "  $(head -1 "$OUT/cover.log")" || problem "no cover window: $(cat "$OUT/cover.log")"
      fi ;;
    click)
      case "${2:-}" in
        little-close) ask="littleClose=point"; mark="little close point:" ;;
        toolbar-empty) ask="toolbarDoubleClick=point"; mark="toolbar empty point:" ;;
        page-top) ask="pageTop=point"; mark="page top point:" ;;
        *) problem "click: unknown target ${2:-}"; continue ;;
      esac
      count=1; [ "${3:-}" = "double" ] && count=2
      [ -x "$OUT/click" ] || clang -fobjc-arc -framework AppKit "$ROOT/scripts/hid-click/click.m" -o "$OUT/click" 2>"$OUT/click-build.log"
      [ -x "$OUT/click" ] || { problem "the click helper did not build (click-build.log)"; continue; }
      seen=$(cat "$DATA"/cra*.log 2>/dev/null | grep -c "$mark")
      send "cra://debug?$ask"
      xy=""
      for _ in $(seq 1 50); do
        [ "$(cat "$DATA"/cra*.log 2>/dev/null | grep -c "$mark")" -gt "$seen" ] && \
          { xy=$(cat "$DATA"/cra*.log | grep "$mark" | tail -1 | sed "s/.*$mark //"); break; }
        sleep 0.2
      done
      case "$xy" in
        [0-9]*" "[0-9]*) out=$("$OUT/click" "$PID" $xy $count) || problem "click $2: $out"; echo "  $out" ;;
        *) problem "click $2: nowhere to click (${xy:-no answer})" ;;
      esac ;;
    bare-helper)
      helper="Cra Helper (${line#bare-helper })"
      exe="$APP/Contents/Frameworks/Cra Framework.framework/Versions/Current/Helpers/$helper.app/Contents/MacOS/$helper"
      if [ ! -x "$exe" ]; then problem "no $helper in the engine"
      else
        "$exe" >"$OUT/bare-helper.log" 2>&1 & hp=$!
        for _ in $(seq 1 50); do kill -0 "$hp" 2>/dev/null || break; sleep 0.2; done
        if kill -0 "$hp" 2>/dev/null; then kill -9 "$hp" 2>/dev/null; wait "$hp" 2>/dev/null; problem "$helper launched bare still runs after 10 s"
        else
          wait "$hp"; hs=$?
          echo "  $helper launched bare: exit $hs"
          [ "$hs" -eq 0 ] || problem "$helper launched bare exited $hs$([ "$hs" -gt 128 ] && echo " (signal $((hs - 128)))")"
        fi
      fi ;;
    replace-app)
      next="$OUT/app-next/Cra.app"
      rm -rf "$OUT/app-next" && mkdir -p "$OUT/app-next" && cp -c -R "$APP" "$next"
      plist="$next/Contents/Info.plist"
      version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist").1"
      /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion 999999999999" "$plist"
      # Its seal covers Info.plist; the app's own signature again (not the engine's), so it starts like the build.
      # The running copy may carry its picked icon (Icon\r and Finder info, AppIconManager), which codesign refuses.
      rm -f "$next/Icon"$'\r' && xattr -cr "$next"
      codesign --force -s - --preserve-metadata=entitlements,flags "$next" >"$OUT/replace-app.log" 2>&1 ||
        problem "replace-app: codesign failed: $(tail -1 "$OUT/replace-app.log")"
      if [ "${2:-}" = chrome ]; then
        versions="$next/Contents/Frameworks/Cra Framework.framework/Versions"
        mv "$versions/$(readlink "$versions/Current")" "$versions/999.0.0.0" && ln -sfn 999.0.0.0 "$versions/Current"
      fi
      rm -rf "$APP" && mv "$next" "$APP"
      echo "  Cra.app replaced by $version${2:+ on another Chrome}" ;;
    fresh|requires|port|seed|env|arg|extension|profile|home|crash-report) ;;
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
read -r launch maxstall over50 over16 < <(cat "$OUT/hitch.earlier" "$HITCH" 2>/dev/null | awk '$2 == "relaunch" { started = 0 }
  $2 == "mark" { started = 1; shooting = ($3 ~ /snapshot=/) }
  $2 == "stall" && shooting { next }
  $2 == "stall" && !started { if ($3 > l) l = $3 }
  $2 == "stall" && started { if ($3 > m) m = $3; if ($3 > 50) n++; if ($3 > 16) f++ }
  END { printf "%d %d %d %d\n", l, m, n, f }' || echo "0 0 0 0")
echo "  stalls: start-up ${launch} ms (budget ${LAUNCHSTALL}); then longest ${maxstall} ms, ${over50} over 50 ms (budget ${MAXSTALL} ms, ${STALLS50})"
[ "${launch:-0}" -le "$LAUNCHSTALL" ] || budget_problem "a ${launch} ms main-thread stall at start-up, budget ${LAUNCHSTALL} ms"
[ "${maxstall:-0}" -le "$MAXSTALL" ] || budget_problem "a ${maxstall} ms main-thread stall, budget ${MAXSTALL} ms"
[ "${over50:-0}" -le "$STALLS50" ] || budget_problem "${over50} stalls over 50 ms, budget ${STALLS50}"
if [ -n "$STALLS16" ]; then
  echo "  dropped frames: ${over16} stalls over 16 ms (budget ${STALLS16})"
  [ "${over16:-0}" -le "$STALLS16" ] || budget_problem "${over16} stalls over 16 ms, budget ${STALLS16}"
fi

# The performance recorder (#91): what it costs, and whether it saw the stalls HitchMonitor saw.
if alive; then
  send "cra://debug?perfReport=$OUT/perf.json"
  for _ in $(seq 1 25); do [ -s "$OUT/perf.json" ] && break; sleep 0.2; done
  hitch250=$(cat "$OUT/hitch.earlier" "$HITCH" 2>/dev/null | awk '$2 == "stall" && $3 >= 250 { n++ } END { print n + 0 }')
  if [ ! -s "$OUT/perf.json" ]; then problem "no perf.json from the performance recorder"
  else
    other_chrome=$(grep -c '^replace-app chrome' "$FILE")
    verdict=$(python3 -I - "$OUT/perf.json" "$PERFCPU" "$hitch250" "$other_chrome" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
cpu, budget, hitch = r["selfCost"]["cpuPct"], float(sys.argv[2]), int(sys.argv[3])
m = r["mainThread"]
seen = m["freezes"] + m["outsideFreezes"]
print(f"perf: recording costs {cpu:.3f} % of a core (budget {budget}); stalls ≥250 ms: recorder {seen}, HitchMonitor {hitch}")
if cpu > budget: print(f"PROBLEM the performance recorder costs {cpu:.3f} % of a core, budget {budget} %")
# This run's HitchMonitor log starts after the launch the recorder also saw; a few either way is timing.
if abs(seen - hitch) > max(2, hitch // 5): print(f"PROBLEM the recorder counted {seen} stalls of 250 ms or more, HitchMonitor {hitch}")
# What the app does, so never a budget: no scenario crashes a page, and a renderer Cra let go
# (tab sleep's discard) is no crash either (0.1.44 counted each one).
ended = r["counters"].get("rendererTerminated", {})
# A Cra.app replaced by one on another Chrome (replace-app chrome) has no helpers for this copy: that is the case.
if sys.argv[4] != "0": ended.pop("launch failed", None)
if ended: print("CRASH pages crashed (“Aw, Snap!”) per the recorder: " + ", ".join(f"{k} ×{n}" for k, n in sorted(ended.items())))
PY
)
    echo "  $(head -1 <<< "$verdict")"
    while IFS= read -r l; do
      [[ "$l" == PROBLEM* ]] && budget_problem "${l#PROBLEM }"
      [[ "$l" == CRASH* ]] && problem "${l#CRASH }"
    done <<< "$verdict"
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
