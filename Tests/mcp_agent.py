#!/usr/bin/env python3
"""Real-app MCP checks for an agent using Cra as it is: hidden tabs, rich editors, frames,
shadow DOM, any key and mouse button, dialogs and the console. Uses a temporary profile and
two localhost servers (two sites), and keeps Cra behind other apps (CRA_TEST_BACKGROUND)."""
import argparse
import base64
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import tempfile
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument("--app", default="build/CraDev.app")
options = parser.parse_args()
app = Path(options.app).resolve()
with (app / "Contents/Info.plist").open("rb") as file:
    executable = app / "Contents/MacOS" / plistlib.load(file)["CFBundleExecutable"]
# Short: a Unix socket path holds at most 104 bytes.
folder = Path(tempfile.mkdtemp(prefix="cra-mcp-agent-", dir="/tmp"))
profile = folder / "data"
profile.mkdir()
(profile / "settings.json").write_text(json.dumps({"hasSeenImportPrompt": True, "toolbarDefaultMigrated": True}))
commands = folder / "commands"
commands.touch()
socket_path = profile / "mcp.sock"
fixtures = Path(__file__).parent / "Fixtures/MCP"
checks = []

def check(name, condition, detail=None):
    assert condition, name + (": " + json.dumps(detail)[:800] if detail is not None else "")
    checks.append(name)
    print("PASS " + name, flush=True)

def eventually(predicate, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(.1)
    raise AssertionError("Condition timed out")

class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.split("?")[0].lstrip("/") or "agent.html"
        page = fixtures / name
        if not page.is_file():
            self.send_response(404); self.end_headers(); return
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(page.read_bytes())
    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        self.rfile.read(length)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')
    def log_message(self, *args):
        pass

servers = [http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixture) for _ in range(2)]
for server in servers:
    threading.Thread(target=server.serve_forever, daemon=True).start()
url = "http://127.0.0.1:" + str(servers[0].server_port)
other_site = servers[1].server_port  # served as localhost: another site, so another process

environment = dict(os.environ, CRA_DATA_DIR=str(profile), CRA_COMMAND_FILE=str(commands), CRA_TEST_BACKGROUND="1")
log = (folder / "browser.log").open("ab")
process = subprocess.Popen([str(executable), "-mcpEnabled", "YES", "-mcpAllowsScripts", "YES"], env=environment, stdout=log, stderr=log)

def listening():
    try:
        with socket.socket(socket.AF_UNIX) as probe:
            probe.connect(str(socket_path))
        return True
    except OSError:
        return False

class Client:
    def __init__(self, name="cra-agent"):
        self.proc = subprocess.Popen([str(executable), "--mcp", str(socket_path)], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.next_id = 0
        assert "result" in self.call("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": name, "version": "1"}})
        self.proc.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
        self.proc.stdin.flush()
    def call(self, method, params=None):
        self.next_id += 1
        message = {"jsonrpc": "2.0", "id": self.next_id, "method": method}
        if params is not None:
            message["params"] = params
        self.proc.stdin.write(json.dumps(message).encode() + b"\n")
        self.proc.stdin.flush()
        return json.loads(self.proc.stdout.readline())
    def tool(self, tool_name, /, **arguments):
        started = time.monotonic()
        response = self.call("tools/call", {"name": tool_name, "arguments": arguments})
        response["seconds"] = time.monotonic() - started
        return response
    def close(self):
        self.proc.stdin.close()
        self.proc.wait(timeout=10)

def value(response):
    assert "result" in response and not response["result"]["isError"], response
    return json.loads(response["result"]["content"][0]["text"])

def failure(response):
    return response.get("error", {}).get("message") or (response["result"]["isError"] and response["result"]["content"][0]["text"])

def activations():
    """How often Cra asked to come to the front while in the background (the test copy refuses)."""
    label = "a" + str(time.monotonic_ns())
    with commands.open("a") as file:
        file.write("cra://debug?activations=" + label + "\n")
    line = eventually(lambda: next((l for l in (folder / "browser.log").read_text(errors="replace").splitlines() if "activations " + label + ":" in l), None))
    if "active=1" in line:
        return None  # Cra is the active app already (nothing else is in front): requests aren't counted
    return int(line.rsplit("background=", 1)[1].split()[0])

def activation_check(name, condition_from, before):
    """An activation check, skipped when Cra was or became the active app and couldn't count."""
    after = activations()
    if before is None or after is None:
        print("SKIP " + name + " (the test copy is the active app; nothing else is in front)", flush=True)
        return
    check(name, condition_from(before, after))

def command(line):
    with commands.open("a") as file:
        file.write(line + "\n")

def window_titles():
    script = ("import CoreGraphics; let l = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as! [[String: Any]]; "
              "for w in l where (w[kCGWindowOwnerPID as String] as? Int32) == " + str(process.pid) + " { print(w[kCGWindowName as String] as? String ?? \"\") }")
    return subprocess.run(["swift", "-e", script], capture_output=True, text=True).stdout

try:
    eventually(listening, timeout=30)
    client = Client()
    # A new agent gets nothing until the user allows it; Cra asks once and remembers.
    asked = client.tool("tabs_list")
    check("a new agent waits for the user's answer", "asking the user to allow cra-agent" in failure(asked))
    check("Cra asks the user", eventually(lambda: "Let \u201ccra-agent\u201d use Cra?" in window_titles(), timeout=20))
    command("cra://debug?mcpAnswer=allow")
    eventually(lambda: not client.tool("tabs_list")["result"]["isError"])
    client.close()
    client = Client()
    check("an allowed agent is remembered", not client.tool("tabs_list")["result"]["isError"])
    stranger = Client("other-agent")
    stranger.tool("tabs_list")
    eventually(lambda: "other-agent" in window_titles(), timeout=20)
    command("cra://debug?mcpAnswer=deny")
    check("refusing an agent closes its connection", eventually(lambda: stranger.proc.poll() is not None))
    stranger = Client("other-agent")
    check("a refused agent is refused again", "didn't allow other-agent" in failure(stranger.tool("tabs_list")))
    stranger.close()

    check("32 tools advertised (history off)", len(client.call("tools/list")["result"]["tools"]) == 32)
    command("cra://debug?mcpScripts=off")
    eventually(lambda: len(client.call("tools/list")["result"]["tools"]) == 31)
    check("page_evaluate is off unless the user turns it on", "page_evaluate is off" in failure(client.tool("page_evaluate", tabId="x", expression="1")))
    command("cra://debug?mcpScripts=on")
    eventually(lambda: len(client.call("tools/list")["result"]["tools"]) == 32)
    def js(tab, expression):
        return value(client.tool("page_evaluate", tabId=tab, expression=expression))["result"].get("value")
    def events(tab):
        return js(tab, "window.events || []")

    # The user's tab is on screen; the agent opens its own in the background.
    before = activations()
    user_tab = value(client.tool("tab_open", url=url + "/index.html", select=True))["tabId"]
    tab = value(client.tool("tab_open", url=url + "/agent.html?cross=" + str(other_site)))["tabId"]
    activation_check("tab_open never asks to bring Cra forward", lambda b, a: a == b, before)
    value(client.tool("page_wait", tabId=tab, text="Bottom button"))
    listed = {t["id"]: t for t in value(client.tool("tabs_list"))}
    check("agent tab opens unselected in the today list", not listed[tab].get("selected") and listed[tab]["section"] == "today" and listed[tab]["space"])
    check("tabs_list marks the user's tab active", listed[user_tab].get("active") is True and listed[user_tab].get("selected") is True)
    check("a hidden tab works as a focused visible page", js(tab, "document.visibilityState + document.hasFocus()") == "visibletrue")

    # Everything below happens in the hidden tab.
    value(client.tool("page_click", tabId=tab, selector="#bottom"))
    check("click in a hidden tab", "bottom clicked" in events(tab))
    shot = client.tool("page_screenshot", tabId=tab)["result"]
    image = base64.b64decode(shot["content"][0]["data"])
    size = json.loads(shot["content"][1]["text"])
    check("screenshot of a hidden tab, with its coordinate size", not shot["isError"] and image[:3] == b"\xff\xd8\xff" and size["width"] > 0 and size["height"] > 0)

    snapshot = value(client.tool("page_snapshot", tabId=tab))
    elements = snapshot["elements"]
    ref = lambda name: next(e["ref"] for e in elements if e.get("name") == name and e.get("ref"))
    check("snapshot reaches open shadow roots", any(e["name"] == "Shadow button" for e in elements))
    check("snapshot includes same-site iframe content", snapshot["frames"] >= 1 and any(e["name"] == "Frame button" and e.get("frame") == 1 for e in elements))
    check("snapshot marks the cross-site iframe", any(e.get("crossSite") for e in elements))

    value(client.tool("page_click", tabId=tab, ref=ref("Shadow button")))
    check("shadow DOM click by ref", "shadow click trusted=true" in events(tab))
    value(client.tool("page_type", tabId=tab, ref=ref("Shadow input"), text="hej"))
    check("shadow DOM typing by ref", "shadow input=hej" in events(tab))

    value(client.tool("page_type", tabId=tab, selector="#rich", text=" and more"))
    check("rich editor typing appends", js(tab, "document.getElementById('rich').innerText.replace(/\\s+/g,' ').trim()") == "Hello world and more")
    value(client.tool("page_type", tabId=tab, text="!"))
    check("typing without a target goes to focus", js(tab, "document.getElementById('rich').innerText").rstrip().endswith("more!"))
    value(client.tool("page_fill", tabId=tab, selector="#rich", text="Line one\nLine two"))
    check("rich editor fill replaces content with lines", js(tab, "document.getElementById('rich').innerText.replace(/\\n+/g,'|').trim()") == "Line one|Line two")
    letter = ("Dear team, this is a long message. " * 40)[:1200]
    filled = client.tool("page_fill", tabId=tab, selector="#rich", text=letter)
    value(filled)
    check("1,200 characters go into a rich editor in under 3 s", filled["seconds"] < 3 and js(tab, "document.getElementById('rich').innerText.replace(/\\s+/g,' ').trim()") == letter.strip())
    long_text = ("Lorem ipsum dolor sit amet. " * 400)[:10000]
    filled = client.tool("page_fill", tabId=tab, selector="#long", text=long_text)
    value(filled)
    check("10,000 characters fill a textarea in under 3 s", filled["seconds"] < 3 and js(tab, "document.getElementById('long').value.length") == 10000)
    check("over 20,000 characters is refused with a reason", "20000 characters" in failure(client.tool("page_type", tabId=tab, selector="#long", text="x" * 20001)))

    value(client.tool("page_type", tabId=tab, selector="#q", text="cra mcp\n"))
    check("a newline in a search box submits it", "searched=cra mcp" in events(tab))
    small = js(tab, "scrollY")
    value(client.tool("page_scroll", tabId=tab, dy=12))
    check("a small scroll is one real wheel step", js(tab, "scrollY") != small)
    compact = value(client.tool("page_snapshot", tabId=tab, interactive=True))["elements"]
    check("interactive snapshot keeps controls only", compact and all(e["role"] not in ("StaticText", "paragraph") for e in compact) and any(e["name"] == "Bottom button" for e in compact))
    found = value(client.tool("page_snapshot", tabId=tab, query="frame input"))["elements"]
    check("snapshot query finds by name, frames included", [e["name"] for e in found] == ["Frame input"])
    check("tab_open in an unknown space names the spaces", "Spaces:" in failure(client.tool("tab_open", url=url + "/index.html", space="No such space")))
    named = value(client.tool("tab_open", url=url + "/index.html", space=listed[tab]["space"].upper()))["tabId"]
    check("tab_open in a named space", next(t for t in value(client.tool("tabs_list")) if t["id"] == named)["space"] == listed[tab]["space"])
    value(client.tool("tab_close", tabId=named))

    value(client.tool("page_click", tabId=tab, selector="#dbl", clickCount=2))
    check("double click", "dblclick trusted=true" in events(tab))
    value(client.tool("page_click", tabId=tab, selector="#dbl", modifiers="Meta"))
    check("modifier click", "meta click trusted=true" in events(tab))
    value(client.tool("page_click", tabId=tab, selector="#ctx", button="right"))
    check("right click", "contextmenu trusted=true" in events(tab))
    value(client.tool("page_click", tabId=tab, selector="#menu-free", button="right"))
    time.sleep(.8)
    menus = subprocess.run(["swift", "-e", "import CoreGraphics; let l = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]; print(l.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == " + str(process.pid) + " && ($0[kCGWindowLayer as String] as? Int ?? 0) == 101 }.count)"], capture_output=True, text=True).stdout.strip()
    check("right click opens no native menu over the screen", "free contextmenu trusted=true" in events(tab) and menus == "0", menus)
    value(client.tool("page_click", tabId=tab, selector="#middle", button="middle"))
    check("middle click", "auxclick button=1 trusted=true" in events(tab))
    value(client.tool("page_press", tabId=tab, key="k", modifiers="Meta"))
    check("⌘K reaches the page", "cmd-k trusted=true" in events(tab))
    value(client.tool("page_fill", tabId=tab, selector="#kb", text="select me"))
    value(client.tool("page_press", tabId=tab, key="a", modifiers="Meta"))
    value(client.tool("page_type", tabId=tab, text="replaced"))
    check("⌘A selects, as on the Mac", js(tab, "document.getElementById('kb').value") == "replaced")
    check("an unknown key is refused with a reason", "not a key name" in failure(client.tool("page_press", tabId=tab, key="Hyper")))

    value(client.tool("page_select", tabId=tab, selector="#country", label="Spain"))
    check("select by label among shared initials", js(tab, "document.getElementById('country').value") == "es")
    passed = value(client.tool("page_select", tabId=tab, selector="#country", label="Deutschland"))
    check("select reports options typed through", js(tab, "document.getElementById('country').value") == "de2" and "passed through" in passed.get("note", ""))

    box = js(tab, "(() => { const c = document.getElementById('canvas'); c.scrollIntoView({block:'center'}); const r = c.getBoundingClientRect(); return [r.left, r.top]; })()")
    assert not client.tool("page_screenshot", tabId=tab)["result"]["isError"]
    at = value(client.tool("page_click", tabId=tab, x=box[0] + 230, y=box[1] + 40))
    check("x/y click lands on canvas", "canvas green hit" in events(tab) and at["target"].get("tag") == "CANVAS", at)

    value(client.tool("page_click", tabId=tab, ref=ref("Frame button")))
    check("same-site iframe click by ref", eventually(lambda: "frame click trusted=true" in events(tab)))
    value(client.tool("page_type", tabId=tab, ref=ref("Frame input"), text="in frame"))
    check("same-site iframe typing by ref", eventually(lambda: "frame input=in frame" in events(tab)))
    js(tab, "window.events = []")
    frame = js(tab, "(() => { const f = document.getElementById('cross'); f.scrollIntoView({block:'center'}); const r = f.getBoundingClientRect(); return [r.left, r.top]; })()")
    at = value(client.tool("page_click", tabId=tab, x=frame[0] + 40, y=frame[1] + 15))
    check("cross-site iframe click by x/y", eventually(lambda: "frame click trusted=true" in events(tab)) and at["target"].get("tag") == "IFRAME", at)

    value(client.tool("page_hover", tabId=tab, selector="#hov"))
    value(client.tool("page_click", tabId=tab, selector="#revealed"))
    check("hover opens what it reveals", "revealed clicked" in events(tab))
    check("x/y outside the viewport is refused", "outside the viewport" in failure(client.tool("page_click", tabId=tab, x=99999, y=5)))
    check("a hidden element is refused in plain words", "isn't shown on the page" in failure(client.tool("page_fill", tabId=tab, selector="#panel input", text="x")))

    # Dialogs: the page waits for them; the agent sees them and answers.
    opened = value(client.tool("page_click", tabId=tab, selector="#alert"))
    check("an alert is reported by the click that opened it", opened["status"] == "dialog_opened" and opened["dialog"]["message"] == "Hi from alert")
    blocked = client.tool("page_read", tabId=tab)
    check("other tools say a dialog waits, without hanging", "page_dialog" in failure(blocked) and blocked["seconds"] < 1)
    check("tabs_list shows the dialog", next(t for t in value(client.tool("tabs_list")) if t["id"] == tab).get("dialog", {}).get("type") == "alert")
    value(client.tool("page_dialog", tabId=tab, action="accept"))
    check("alert accepted", eventually(lambda: "alert closed" in events(tab)))
    value(client.tool("page_click", tabId=tab, selector="#confirm"))
    value(client.tool("page_dialog", tabId=tab, action="dismiss"))
    check("confirm dismissed", eventually(lambda: "confirm=false" in events(tab)))
    value(client.tool("page_click", tabId=tab, selector="#prompt"))
    value(client.tool("page_dialog", tabId=tab, action="accept", promptText="Victor"))
    check("prompt answered", eventually(lambda: "prompt=Victor" in events(tab)))
    check("page_dialog without a dialog is an error", "No JavaScript dialog" in failure(client.tool("page_dialog", tabId=tab, action="accept")))

    first = value(client.tool("page_console", tabId=tab))
    check("console capture includes earlier messages", any("fixture: bottom clicked" in e["text"] for e in first["entries"]))
    value(client.tool("page_click", tabId=tab, selector="#warn"))
    errors = eventually(lambda: (lambda e: e if any("boom" in x["text"] for x in e) else None)(value(client.tool("page_console", tabId=tab, level="warning"))["entries"]))
    check("console reports warnings and uncaught errors", any(e["level"] == "warning" and "fixture warning" in e["text"] for e in errors) and any(e["level"] == "error" and "fixture boom" in e["text"] for e in errors))

    # Instant input by default; paced like a person only when asked.
    fast = client.tool("page_fill", tabId=tab, selector="#long", text="The quick brown fox jumps over the lazy dog, again and again.")
    value(fast)
    paced = client.tool("page_fill", tabId=tab, selector="#long", text="slow typing", humanize=True)
    value(paced)
    check("input is instant unless humanized", fast["seconds"] < 1.0 and paced["seconds"] > 0.25, [fast["seconds"], paced["seconds"]])

    # Each action says what it changed: the panel's new fields with refs, and the form post.
    opened = value(client.tool("page_click", tabId=tab, selector="#open-panel"))
    added = opened["changes"].get("added", [])
    check("a click reports the elements it revealed, with refs", any(line.startswith('textbox "Panel title"') and " e-" in line for line in added), opened["changes"])
    posted = value(client.tool("page_click", tabId=tab, selector="#post"))
    network = posted["changes"].get("network", [])
    check("a click reports its form post, token hidden", any(n["method"] == "POST" and "token=…" in n["url"] and "hunter2" not in n["url"] and n.get("status") == "200" for n in network), posted["changes"])
    quiet = value(client.tool("page_click", tabId=tab, selector="#dbl", changes=False))
    check("changes=false skips the report", "changes" not in quiet)

    # A field the page replaces when it's clicked (Wikipedia's search box) is followed.
    swapped = value(client.tool("page_type", tabId=tab, selector="#swap", text="cra"))
    check("typing follows a field replaced on focus", "retargeted" in swapped and js(tab, "document.getElementById('swap-live').value") == "cra", swapped)
    elements = value(client.tool("page_snapshot", tabId=tab))["elements"]
    old_ref = next(e["ref"] for e in elements if e["name"] == "Redraw me")
    value(client.tool("page_click", tabId=tab, selector="#redraw"))
    stale = failure(client.tool("page_click", tabId=tab, ref=old_ref))
    check("a stale ref names its redrawn element", "redrew it" in stale and "e-" in stale.split("redrew it")[1], stale)

    # Date, time, colour and range take their value directly.
    value(client.tool("page_fill", tabId=tab, selector="#date", text="2026-11-09"))
    value(client.tool("page_fill", tabId=tab, selector="#time", text="2:30 PM"))
    value(client.tool("page_fill", tabId=tab, selector="#color", text="#3B82F6"))
    value(client.tool("page_fill", tabId=tab, selector="#range", text="40"))
    check("typed inputs take their values", js(tab, "[date.value, time.value, color.value, range.value].join(' ')") == "2026-11-09 14:30 #3b82f6 40")
    check("a value in the wrong format is refused", "takes 2026-11-09" in failure(client.tool("page_fill", tabId=tab, selector="#date", text="9 Nov")))

    # Custom dropdowns: a typeahead and a button that opens a listbox.
    picked = value(client.tool("page_select", tabId=tab, selector="#fruit", label="Banana"))
    check("a typeahead combobox picks its option", "fruit=Banana trusted=true" in events(tab), picked)
    value(client.tool("page_select", tabId=tab, selector="#size", label="Medium"))
    check("a button's listbox picks its option", "size=Medium" in events(tab))
    check("an option that isn't there is refused with what shows", "Showing: Small | Medium | Large" in failure(client.tool("page_select", tabId=tab, selector="#size", label="Huge")))

    # Several steps in one call; the first failure stops the rest.
    batch = client.tool("page_batch", tabId=tab, steps=[
        {"tool": "page_fill", "arguments": {"selector": "#kb", "text": "batched"}},
        {"tool": "page_click", "arguments": {"selector": "#missing"}},
        {"tool": "page_read", "arguments": {}}])
    texts = [c["text"] for c in batch["result"]["content"] if c["type"] == "text"]
    check("page_batch runs steps in order and stops at a failure", batch["result"]["isError"] and texts[0].startswith("1. page_fill: ")
          and texts[1].startswith("2. page_click failed") and texts[2] == "3. page_read: not run" and js(tab, "document.getElementById('kb').value") == "batched", texts)

    # The network log: writes only, token hidden, no headers.
    started = value(client.tool("page_network", tabId=tab))
    value(client.tool("page_click", tabId=tab, selector="#post", changes=False))
    writes = eventually(lambda: value(client.tool("page_network", tabId=tab, writesOnly=True))["requests"])
    check("page_network logs requests with tokens hidden", "Capture started" in started.get("note", "") and writes[-1]["method"] == "POST" and "token=…" in writes[-1]["url"], writes)

    # Site notes: kept per site, shown at the top of snapshots.
    value(client.tool("site_notes", action="set", tabId=tab, text="The fixture's search form submits on Enter."))
    noted = value(client.tool("page_snapshot", tabId=tab, interactive=True))
    check("a snapshot starts with the site's notes", "submits on Enter" in noted.get("notes", {}).get("text", ""), noted.get("notes"))
    value(client.tool("site_notes", action="append", site="127.0.0.1:" + str(servers[0].server_port), text="Second line."))
    got = value(client.tool("site_notes", action="get", site="127.0.0.1:" + str(servers[0].server_port)))
    check("notes append and read back", got["notes"] == "The fixture's search form submits on Enter.\nSecond line.")
    check("notes are listed", any(n["site"] == "127.0.0.1:" + str(servers[0].server_port) for n in value(client.tool("site_notes", action="list"))["sites"]))
    check("a path isn't a site", "needs a site" in failure(client.tool("site_notes", action="get", site="../../etc")))
    value(client.tool("site_notes", action="delete", tabId=tab))

    # History: off until the user turns it on.
    check("history_search is off by default", "history_search is off" in failure(client.tool("history_search", query="agent fixture")))
    command("cra://debug?mcpHistory=on")
    found = eventually(lambda: (lambda r: r if not r["result"]["isError"] and value(r)["count"] else None)(client.tool("history_search", query="agent fixture")))
    check("history_search finds visited pages", any("agent.html" in e["url"] for e in value(found)["entries"]))
    command("cra://debug?mcpHistory=off")

    # Organizing tabs like the sidebar does.
    spare = value(client.tool("tab_open", url=url + "/index.html?spare"))["tabId"]
    value(client.tool("page_wait", tabId=spare))
    value(client.tool("tab_move", tabId=spare, section="pinned"))
    row = lambda: next(t for t in value(client.tool("tabs_list")) if t["id"] == spare)
    check("tab_move pins a tab", row()["section"] == "pinned")
    value(client.tool("folder_create", name="Agent work", tabIds=[spare]))
    check("folder_create puts tabs in a new folder", row().get("folder") == "Agent work")
    value(client.tool("tab_update", tabId=spare, title="Renamed by agent", muted=True))
    check("tab_update renames", row()["title"] == "Renamed by agent")
    value(client.tool("tab_update", tabId=spare, sleep=True))
    check("tab_update puts a hidden tab to sleep", not row()["loaded"])
    value(client.tool("tab_update", tabId=spare, sleep=False))
    check("and wakes it in the background", eventually(lambda: row()["loaded"]))
    value(client.tool("tab_move", tabId=spare, section="today"))
    check("tab_move unpins it again", row()["section"] == "today" and "folder" not in row())
    check("tab_move names the spaces when one isn't found", "Spaces:" in failure(client.tool("tab_move", tabId=spare, space="Nowhere")))

    # Pages can't tell an agent is there. (Console capture's Runtime domain stays off until asked;
    # Chromium 156 no longer reads the Error.stack bait pages once used to spot it, so it isn't checked.)
    probe = value(client.tool("tab_open", url=url + "/probe.html"))["tabId"]
    value(client.tool("page_wait", tabId=probe, selector="#button", state="visible"))
    time.sleep(.5)
    loaded = js(probe, "probe.mutations")  # what the page and Cra did while it loaded
    value(client.tool("page_snapshot", tabId=probe))
    value(client.tool("page_click", tabId=probe, selector="#button"))
    value(client.tool("page_fill", tabId=probe, selector="#field", text="hello"))
    value(client.tool("page_read", tabId=probe))
    assert not client.tool("page_screenshot", tabId=probe)["result"]["isError"]
    time.sleep(.5)
    seen = js(probe, "({webdriver: probe.webdriver, mutations: probe.mutations, globals: probe.newGlobals(), clicks: probe.clicks})")
    check("pages see no automation: webdriver, globals or DOM changes", seen["webdriver"] is False and seen["mutations"] == loaded
          and seen["globals"] == [] and seen["clicks"] == 1, seen)
    value(client.tool("tab_close", tabId=probe))

    # Only web pages: a browser or extension page in the sidebar is listed but out of reach.
    command("cra://open?url=chrome://version&background=1")
    browser_page = eventually(lambda: next((t for t in value(client.tool("tabs_list")) if t["url"].startswith("chrome://")), None))
    check("a browser page is marked as not a web page", browser_page.get("webPage") is False)
    check("agents can't work in browser pages", "isn't a web page" in failure(client.tool("page_read", tabId=browser_page["id"])))

    # A sleeping tab wakes in the background for the request that needs it.
    sleepy = value(client.tool("tab_open", url=url + "/index.html?sleepy"))["tabId"]
    value(client.tool("page_wait", tabId=sleepy))
    time.sleep(2.5)
    with commands.open("a") as file:
        file.write("cra://debug?sleepTabs=1\n")
    eventually(lambda: not next(t for t in value(client.tool("tabs_list")) if t["id"] == sleepy)["loaded"])
    woken = client.tool("page_read", tabId=sleepy)
    check("a sleeping tab wakes for the request that needs it", "MCP" in value(woken)["text"] and next(t for t in value(client.tool("tabs_list")) if t["id"] == sleepy)["loaded"])
    value(client.tool("tab_close", tabId=sleepy))

    before = activations()
    value(client.tool("tab_show", tabId=tab))
    check("tab_show selects the tab", next(t for t in value(client.tool("tabs_list")) if t["id"] == tab).get("selected"))
    activation_check("tab_show never asks to bring Cra forward", lambda b, a: a == b, before)
    value(client.tool("tab_show", tabId=user_tab, activate=True))
    time.sleep(.5)
    activation_check("activate=true does ask to bring Cra forward", lambda b, a: a > b, before)
    value(client.tool("tab_close", tabId=user_tab))
    check("a today tab closes", user_tab not in [t["id"] for t in value(client.tool("tabs_list"))])

    # The pill: Cra's toast names the agent while it acts; Stop ends every connection and MCP.
    check("acting shows the pill with the agent's name", "mcp pill: cra-agent is using Cra" in (folder / "browser.log").read_text(errors="replace"))
    command("cra://debug?mcpStop=1")
    check("Stop disconnects agents and turns MCP off", eventually(lambda: client.proc.poll() is not None or not listening()) and eventually(lambda: not listening()))
    print("ALL " + str(len(checks)) + " CHECKS PASSED", flush=True)
finally:
    if process.poll() is None:
        with commands.open("a") as file:
            file.write("cra://debug?quit=1\n")
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.kill()
    for server in servers:
        server.shutdown()
    print("ARTIFACT " + str(folder), flush=True)
