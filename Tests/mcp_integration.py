#!/usr/bin/env python3
"""Real-app MCP regression suite. Uses only a temporary profile and local HTTP fixture."""
import argparse
import http.server
import json
import os
from pathlib import Path
import plistlib
import select
import socket
import subprocess
import tempfile
import threading
import time
from urllib.parse import quote

parser = argparse.ArgumentParser()
parser.add_argument("--app", default="build/CraDev.app")
parser.add_argument("--pause-before-input", action="store_true", help="Wait for a start-input file after focusing the test window.")
parser.add_argument("--hold", action="store_true", help="Keep the isolated instance for a real MCP client; Ctrl-C cleans up.")
options = parser.parse_args()
app = Path(options.app).resolve()
with (app / "Contents/Info.plist").open("rb") as file:
    executable = app / "Contents/MacOS" / plistlib.load(file)["CFBundleExecutable"]
folder = Path(tempfile.mkdtemp(prefix="cra-mcp-integration-", dir="/tmp"))
profile = folder / "data"
profile.mkdir()
(profile / "settings.json").write_text(json.dumps({"hasSeenImportPrompt": True, "toolbarDefaultMigrated": True}))
commands = folder / "commands"
commands.touch()
socket_path = profile / "mcp.sock"
log = (folder / "browser.log").open("ab")
process = None
clients = []
checks = []
seen_paths = set()

def check(name, condition):
    assert condition, name
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
        seen_paths.add(self.path)
        if self.path == "/slow-navigation": time.sleep(.5)
        page = (Path(__file__).parent / "Fixtures/MCP/index.html").read_text()
        if self.path == "/transfers":
            page = (Path(__file__).parent / "Fixtures/MCP/transfers.html").read_text()
        if self.path == "/secret":
            page = "<title>Private MCP fixture</title><h1>Private content</h1>"
        if self.path == "/download/sample.txt":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Disposition", 'attachment; filename="sample.txt"')
            self.end_headers()
            self.wfile.write(b"Cra playground: a local synthetic download.\n")
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(page.encode())
    def log_message(self, *args):
        pass

http = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
threading.Thread(target=http.serve_forever, daemon=True).start()
url = "http://127.0.0.1:" + str(http.server_port)

def command(value):
    with commands.open("a") as file:
        file.write(value + "\n")

def launch(enabled):
    global process
    environment = dict(os.environ, CRA_DATA_DIR=str(profile), CRA_COMMAND_FILE=str(commands), CRA_TEST_BACKGROUND="0")
    process = subprocess.Popen([str(executable), "-mcpEnabled", "YES" if enabled else "NO"],
                               env=environment, stdout=log, stderr=log)
    marker = ("pid " + str(process.pid) + " reads commands from CRA_COMMAND_FILE").encode()
    eventually(lambda: marker in (folder / "browser.log").read_bytes())
    if enabled:
        def listening():
            try:
                with socket.socket(socket.AF_UNIX) as probe:
                    probe.connect(str(socket_path))
                return True
            except OSError:
                return False
        eventually(listening)
    else:
        check("disabled server has no socket", not socket_path.exists())

def quit_browser():
    if process is not None and process.poll() is None:
        command("cra://debug?quit=1")
        try:
            process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
            raise AssertionError("Browser did not quit cleanly")

class Client:
    def __init__(self):
        self.proc = subprocess.Popen([str(executable), "--mcp", str(socket_path)],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.next_id = 0
        clients.append(self)
        result = self.call("initialize", {"protocolVersion": "2025-11-25", "capabilities": {},
                                         "clientInfo": {"name": "cra-integration", "version": "1"}})
        assert "result" in result, result
        self.proc.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
        self.proc.stdin.flush()
    def call(self, method, params=None):
        self.next_id += 1
        request = {"jsonrpc": "2.0", "id": self.next_id, "method": method}
        if params is not None:
            request["params"] = params
        self.proc.stdin.write(json.dumps(request).encode() + b"\n")
        self.proc.stdin.flush()
        assert select.select([self.proc.stdout], [], [], 125)[0], "MCP response timeout"
        line = self.proc.stdout.readline()
        if not line:
            raise EOFError("MCP connection closed")
        response = json.loads(line)
        assert response["id"] == self.next_id
        return response
    def tool(self, name, arguments=None):
        return self.call("tools/call", {"name": name, "arguments": arguments or {}})
    def close(self):
        if self.proc.poll() is None:
            self.proc.stdin.close()
            self.proc.wait(timeout=5)

def value(response):
    assert not response.get("error"), response
    result = response["result"]
    assert not result.get("isError"), result
    return json.loads(result["content"][0]["text"])

def tabs(client):
    return value(client.tool("tabs_list"))

def evaluate(client, tab, expression):
    return client.tool("page_evaluate", {"tabId": tab, "expression": expression})

try:
    launch(False)
    unavailable = subprocess.run([str(executable), "--mcp", str(socket_path)], input=b"", capture_output=True, timeout=5)
    check("disabled bridge fails without stdout", unavailable.returncode != 0 and not unavailable.stdout)
    quit_browser()
    launch(True)
    client = Client()
    check("24 tools advertised", len(client.call("tools/list")["result"]["tools"]) == 24)
    check("socket mode 0600", socket_path.stat().st_mode & 0o777 == 0o600)
    command("cra://open?url=" + quote(url + "/regression", safe=""))
    tab = eventually(lambda: next((t["id"] for t in tabs(client) if t["url"] == url + "/regression"), None))
    eventually(lambda: "/regression" in seen_paths)
    def read_page():
        result = client.tool("page_read", {"tabId": tab})
        if result["result"].get("isError"):
            return ""
        return value(result)["text"]
    eventually(lambda: "MCP integration" in read_page())
    check("read existing page", True)
    piped = [
      {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"eof","version":"1"}}},
      {"jsonrpc":"2.0","method":"notifications/initialized"},
      {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"page_read","arguments":{"tabId":tab}}}
    ]
    eof = subprocess.run([str(executable), "--mcp", str(socket_path)], input=b"".join(json.dumps(r).encode()+b"\n" for r in piped), capture_output=True, timeout=20)
    eof_responses = [json.loads(line) for line in eof.stdout.splitlines()]
    check("page read drains successfully after stdin EOF", any(r.get("id") == 2 and not r.get("result", {}).get("isError", True) for r in eof_responses))
    if options.pause_before_input:
        print("INPUT_READY " + str(folder / "start-input"), flush=True)
        eventually(lambda: (folder / "start-input").exists(), timeout=180)
    def input_tool(name, selector, **args):
        return client.tool(name, dict(tabId=tab, selector=selector, **args))
    # Activate through the public MCP tool after the optional human-ready pause.
    # macOS can occlude a just-launched window while the terminal regains focus.
    value(client.tool("tab_show", {"tabId": tab}))
    eventually(lambda: value(evaluate(client, tab, "document.visibilityState === 'visible' && document.hasFocus()"))["result"]["value"])
    result = value(input_tool("page_fill", "#name", text="Mäx 🦊"))
    check("native fill confirms trusted input", result["trustedEvents"]["input"] >= 5)
    value(input_tool("page_press", "#name", key="End"))
    value(input_tool("page_type", "#name", text="!"))
    value(input_tool("page_click", "#go"))
    result = value(evaluate(client, tab, "document.querySelector('#out').textContent"))
    check("native Unicode typing and click", result["result"]["value"] == "Mäx 🦊!")
    value(input_tool("page_fill", "#name", text="abcd"))
    value(input_tool("page_press", "#name", key="Home"))
    value(input_tool("page_press", "#name", key="ArrowRight"))
    value(input_tool("page_type", "#name", text="X"))
    check("typing preserves the established caret", value(evaluate(client, tab, "document.querySelector('#name').value"))["result"]["value"] == "aXbcd")
    events = value(evaluate(client, tab, "window.inputEvents"))["result"]["value"]
    check("fixture sees trusted mouse and keyboard", all(e["trusted"] for e in events) and {"mousedown", "mouseup", "click", "keydown", "keyup", "input"}.issubset({e["type"] for e in events}))
    downs = [e["time"] for e in events if e["type"] == "keydown"]
    gaps = [b-a for a,b in zip(downs,downs[1:])]
    check("typing has paced variable intervals", len(gaps) > 3 and min(gaps) >= 20 and max(gaps)-min(gaps) > 5)
    check("pointer follows multiple intermediate points", sum(e["type"] == "mousemove" for e in events) > 10)
    value(input_tool("page_fill", "#name", text="replacement"))
    check("native fill replaces existing content", value(evaluate(client, tab, "document.querySelector('#name').value"))["result"]["value"] == "replacement")
    value(input_tool("page_fill", "#name", text=""))
    check("empty fill clears field", value(evaluate(client, tab, "document.querySelector('#name').value"))["result"]["value"] == "")
    for selector in ["#missing", "button", "#disabled", "#hidden", "#covered", "#readonly", "#inert-field", "#transparent-field"]:
        check("refuses unsafe target " + selector, input_tool("page_fill", selector, text="must not arrive")["result"]["isError"])
    check("rejects unsupported key", "error" in input_tool("page_press", "#name", key="F999"))
    check("rejects oversized text", "error" in input_tool("page_type", "#name", text="x" * 257))
    value(input_tool("page_fill", "#multiline", text="first\nsecond"))
    check("textarea preserves newline", value(evaluate(client, tab, "document.querySelector('#multiline').value"))["result"]["value"] == "first\nsecond")
    check("single-line Enter requires explicit press", input_tool("page_type", "#name", text="bad\nsubmit")["result"]["isError"])
    check("focus replacement aborts input", input_tool("page_fill", "#replace-on-focus", text="must not arrive")["result"]["isError"])
    check("replacement receives no text", value(evaluate(client, tab, "document.querySelector('#replace-on-focus').value"))["result"]["value"] == "")
    value(input_tool("page_fill", "#name", text="Enter submits"))
    value(input_tool("page_press", "#name", key="Enter"))
    check("native Enter submits form", value(evaluate(client, tab, "document.querySelector('#out').textContent"))["result"]["value"] == "Enter submits")
    snapshot = value(client.tool("page_snapshot", {"tabId": tab}))
    (folder / "snapshot.json").write_text(json.dumps(snapshot, indent=2))
    name_ref = next(e["ref"] for e in snapshot["elements"] if e["role"] == "textbox" and e["name"].casefold() == "your name")
    again = value(client.tool("page_snapshot", {"tabId": tab}))
    check("snapshot keeps stable refs", name_ref in [e.get("ref") for e in again["elements"]])
    check("snapshot omits value properties", all("value" not in e for e in snapshot["elements"]))
    value(input_tool("page_fill", "#name", text="snapshot-private-marker"))
    masked = value(client.tool("page_snapshot", {"tabId": tab}))
    check("snapshot omits textbox value descendants", "snapshot-private-marker" not in json.dumps(masked))
    value(client.tool("page_fill", {"tabId": tab, "ref": name_ref, "text": "a👨‍👩‍👧‍👦🇨🇭👍🏽b"}))
    check("ZWJ flags and skin tones roundtrip", value(evaluate(client, tab, "document.querySelector('#name').value"))["result"]["value"] == "a👨‍👩‍👧‍👦🇨🇭👍🏽b")
    value(input_tool("page_fill", "#name", text="abcd"))
    value(input_tool("page_click", "#go"))
    value(input_tool("page_type", "#name", text=" X"))
    check("unfocused typing appends predictably", value(evaluate(client, tab, "document.querySelector('#name').value"))["result"]["value"] == "abcd X")
    value(client.tool("page_press", {"tabId": tab, "key": "ArrowLeft", "modifiers": "Shift"}))
    value(input_tool("page_type", "#name", text="Y"))
    check("modifier key selection replaces selected text", value(evaluate(client, tab, "document.querySelector('#name').value"))["result"]["value"] == "abcd Y")
    before = value(evaluate(client, tab, "window.inputEvents.length"))["result"]["value"]
    rejected = input_tool("page_press", "h1", key="Escape")
    check("nonfocusable target refuses before any input", rejected["result"]["isError"] and value(evaluate(client, tab, "window.inputEvents.length"))["result"]["value"] == before)
    check("press on an unfocused button cannot submit", input_tool("page_press", "#go", key="Tab")["result"]["isError"])
    before_hover = value(evaluate(client, tab, "window.inputEvents.length"))["result"]["value"]
    value(input_tool("page_hover", "#go"))
    hover_events = value(evaluate(client, tab, "window.inputEvents.slice(" + str(before_hover) + ")"))["result"]["value"]
    check("hover reaches target without click", any(e["type"] == "mousemove" and e["trusted"] for e in hover_events) and not any(e["type"] in ("click", "mousedown", "mouseup") for e in hover_events))
    value(input_tool("page_click", "#check"))
    check("native checkbox toggles", value(evaluate(client, tab, "document.querySelector('#check').checked"))["result"]["value"] is True)
    value(input_tool("page_fill", "#rich", text="Plain notes 🦊"))
    check("plain contenteditable input", value(evaluate(client, tab, "document.querySelector('#rich').textContent"))["result"]["value"] == "Plain notes 🦊")
    value(input_tool("page_fill", "#rich", text="Replaced"))
    check("contenteditable replaces content", value(evaluate(client, tab, "document.querySelector('#rich').textContent"))["result"]["value"] == "Replaced")
    value(input_tool("page_fill", "#rich", text="a  b "))
    check("contenteditable preserves repeated and trailing spaces", value(evaluate(client, tab, "document.querySelector('#rich').textContent.replace(/\\u00a0/g,' ')"))["result"]["value"] == "a  b ")
    value(input_tool("page_select", "#choice", value="two"))
    check("native select chooses exact value", value(evaluate(client, tab, "document.querySelector('#choice').value"))["result"]["value"] == "two")
    for option in ("three", "one", "two", "two"):
        value(input_tool("page_select", "#choice", value=option))
        check("repeated native select reaches " + option, value(evaluate(client, tab, "document.querySelector('#choice').value"))["result"]["value"] == option)
    check("unknown select value refuses", input_tool("page_select", "#choice", value="absent")["result"]["isError"])
    value(evaluate(client, tab, "document.querySelector('#choice').insertAdjacentHTML('afterend','<select id=ambiguous-select><option value=band>Bandana</option><option value=banana>Banana</option></select>')"))
    selection_events = value(evaluate(client, tab, "window.inputEvents.length"))["result"]["value"]
    check("ambiguous select refuses without intermediate changes", input_tool("page_select", "#ambiguous-select", value="banana")["result"]["isError"] and value(evaluate(client, tab, "window.inputEvents.length"))["result"]["value"] == selection_events)

    value(input_tool("page_scroll", "#scroll-box", dy=600))
    check("native wheel scrolls nested region", value(evaluate(client, tab, "document.querySelector('#scroll-box').scrollTop"))["result"]["value"] > 0)
    value(input_tool("page_click", "#delay-button"))
    value(client.tool("page_wait", {"tabId": tab, "text": "Ready to continue", "selector": "#delayed-status"}))
    check("wait observes asynchronous page change", True)
    check("wait timeout is a tool error", client.tool("page_wait", {"tabId": tab, "selector": "#absent", "timeoutMs": 100})["result"]["isError"])
    value(client.tool("page_wait", {"tabId": tab, "selector": "#absent", "state": "detached"}))
    check("wait supports detached target", True)
    shot = client.tool("page_screenshot", {"tabId": tab})["result"]
    import base64
    image_data = base64.b64decode(shot["content"][0]["data"])
    (folder / "screenshot.jpg").write_bytes(image_data)
    check("screenshot is an actual MCP JPEG", not shot["isError"] and image_data[:3] == b"\xff\xd8\xff")
    image_info = subprocess.check_output(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(folder / "screenshot.jpg")], text=True)
    dimensions = [int(line.split(":")[-1]) for line in image_info.splitlines() if "pixelWidth:" in line or "pixelHeight:" in line]
    check("Retina screenshot respects pixel budget", len(dimensions) == 2 and max(dimensions) <= 1280)
    pdf = value(client.tool("page_pdf", {"tabId": tab}))
    pdf_path = Path(pdf["path"])
    check("PDF export is private and valid", pdf_path.read_bytes().startswith(b"%PDF-") and pdf_path.stat().st_mode & 0o777 == 0o600 and pdf_path.parent == profile / "mcp-exports")
    # Set up a replacement deliberately; a previously retained ref must never follow it.
    value(evaluate(client, tab, "document.querySelector('#name').replaceWith(document.querySelector('#name').cloneNode(true)); true"))
    check("detached ref cannot retarget replacement", client.tool("page_click", {"tabId": tab, "ref": name_ref})["result"]["isError"])
    # An agent may close its own tabs, never the user's or another connection's tabs.
    check("user tab cannot be closed", client.tool("tab_close", {"tabId": tab})["result"]["isError"])
    agent_tab = value(client.tool("tab_open", {"url": url + "/next?agent=1"}))["tabId"]
    eventually(lambda: any(t["id"] == agent_tab and t["loaded"] for t in tabs(client)))
    value(client.tool("page_wait", {"tabId": agent_tab, "url": url + "/next?agent=1"}))
    check("agent tab opens in existing session", value(evaluate(client, agent_tab, "document.cookie.includes('mcp_fixture=session')"))["result"]["value"] is True)
    foreign = Client()
    check("other connection cannot close agent tab", foreign.tool("tab_close", {"tabId": agent_tab})["result"]["isError"])
    foreign.close()
    value(client.tool("tab_close", {"tabId": agent_tab}))
    check("owner closes its agent tab", agent_tab not in [t["id"] for t in tabs(client)])
    value(client.tool("tab_show", {"tabId": tab}))
    check("tab show restores existing tab", True)
    # Cancellation and ping share the same connection while the input operation is running.
    seen_paths.clear()
    client.next_id += 1
    fill_id = client.next_id
    client.proc.stdin.write(json.dumps({"jsonrpc":"2.0", "id":fill_id, "method":"tools/call", "params":{"name":"page_fill", "arguments":{"tabId":tab,"selector":"#name","text":"c"*200}}}).encode() + b"\n")
    client.proc.stdin.flush()
    eventually(lambda: "/input-progress?length=3" in seen_paths)
    started = time.monotonic()
    check("ping is responsive during input", client.call("ping")["result"] == {} and time.monotonic() - started < 1)
    client.proc.stdin.write(json.dumps({"jsonrpc":"2.0", "method":"notifications/cancelled", "params":{"requestId":fill_id}}).encode() + b"\n")
    client.proc.stdin.flush()
    assert select.select([client.proc.stdout], [], [], 10)[0]
    cancelled = json.loads(client.proc.stdout.readline())
    check("MCP cancellation returns partial-action error", cancelled["id"] == fill_id and cancelled["result"]["isError"])
    check("connection survives cancellation", client.call("ping")["result"] == {})
    check("MCP cancellation stops remaining input", 0 < len(value(evaluate(client, tab, "document.querySelector('#name').value"))["result"]["value"]) < 200)
    # A connection closing mid-gesture must stop typing and release the per-tab lease.
    owner = Client()
    seen_paths.clear()
    owner.next_id += 1
    owner.proc.stdin.write(json.dumps({"jsonrpc":"2.0", "id":owner.next_id, "method":"tools/call", "params":{"name":"page_fill", "arguments":{"tabId":tab, "selector":"#name", "text":"z"*200}}}).encode() + b"\n")
    owner.proc.stdin.flush()
    eventually(lambda: "/input-progress?length=3" in seen_paths)
    check("input is already underway before cancellation", client.tool("page_read", {"tabId":tab})["result"].get("isError"))
    check("concurrent navigation cannot interrupt input", client.tool("page_navigate", {"tabId":tab,"url":url+"/must-not-open"})["result"]["isError"])
    owner.proc.terminate()
    owner.proc.wait(timeout=5)
    eventually(lambda: not client.tool("page_read", {"tabId":tab})["result"].get("isError"))
    check("disconnect cancels remaining typing", 0 < len(value(evaluate(client, tab, "document.querySelector('#name').value"))["result"]["value"]) < 200)
    value(input_tool("page_fill", "#name", text="after disconnect"))
    check("input works after cancelled owner", True)
    value(input_tool("page_click", "#next"))
    eventually(lambda: "/next" in seen_paths)
    check("native link click navigates", True)
    result = value(evaluate(client, tab, "Promise.resolve(document.cookie.includes('mcp_fixture=session'))"))
    check("promise and existing session", result["result"]["value"] is True)
    value(client.tool("page_navigate", {"tabId": tab, "url": url + "/next"}))
    eventually(lambda: "/next" in seen_paths)
    eventually(lambda: value(evaluate(client, tab, "location.pathname"))["result"]["value"] == "/next")
    check("HTTP navigation completes", True)
    value(client.tool("page_navigate", {"tabId": tab, "url": url + "/slow-navigation"}))
    value(client.tool("page_wait", {"tabId": tab}))
    check("wait after navigation cannot match old document", value(evaluate(client, tab, "location.pathname"))["result"]["value"] == "/slow-navigation")
    value(client.tool("page_navigate", {"tabId": tab, "url": url + "/next"}))
    value(client.tool("page_wait", {"tabId": tab, "url": url + "/next"}))
    check("old document refs are rejected", client.tool("page_click", {"tabId": tab, "ref": name_ref})["result"]["isError"])
    value(client.tool("page_navigate", {"tabId": tab, "url": url + "/history-second"}))
    value(client.tool("page_wait", {"tabId": tab, "url": url + "/history-second"}))
    value(client.tool("page_history", {"tabId": tab, "action": "back"}))
    value(client.tool("page_wait", {"tabId": tab, "url": url + "/next"}))
    value(client.tool("page_history", {"tabId": tab, "action": "forward"}))
    value(client.tool("page_wait", {"tabId": tab, "url": url + "/history-second"}))
    value(client.tool("page_history", {"tabId": tab, "action": "reload"}))
    value(client.tool("page_wait", {"tabId": tab, "text": "MCP integration"}))
    check("history back forward and reload", True)
    value(client.tool("page_navigate", {"tabId": tab, "url": url + "/#same"}))
    value(client.tool("page_wait", {"tabId": tab, "url": url + "/#same"}))
    value(client.tool("page_navigate", {"tabId": tab, "url": url + "/#same"}))
    check("same-fragment no-op navigation has bounded wait", client.tool("page_wait", {"tabId": tab, "timeoutMs": 100})["result"]["isError"])
    value(client.tool("page_wait", {"tabId": tab, "url": url + "/#same"}))
    check("wait recovers after navigation never commits", True)
    value(client.tool("page_navigate", {"tabId": tab, "url": url + "/#different"}))
    value(client.tool("page_wait", {"tabId": tab, "url": url + "/#different"}))
    check("same-document fragment navigation is observed", value(client.tool("page_read", {"tabId": tab}))["url"] == url + "/#different")
    value(evaluate(client, tab, "document.body.insertAdjacentHTML('beforeend','<svg><a href=/svg-link><text>SVG link</text></a></svg>')"))
    check("page read tolerates SVG links", "MCP integration" in value(client.tool("page_read", {"tabId": tab}))["text"])

    value(evaluate(client, tab, "document.body.innerText='漢'.repeat(150000); true"))
    offset = 0
    recovered_text = ""
    while True:
        part = value(client.tool("page_read", {"tabId": tab, "offset": offset}))
        recovered_text += part["text"]
        if part["nextOffset"] is None: break
        offset = part["nextOffset"]
    check("large CJK page reads without truncation", recovered_text == "漢" * 150000)
    value(evaluate(client, tab, "document.body.innerHTML='<a href=\"/\">'+ 'x'.repeat(149)+'🦊</a>'; true"))
    cut = value(client.tool("page_read", {"tabId": tab, "offset": 150}))
    check("read never splits surrogate pairs", cut["text"] == "" and cut["links"][0]["text"] == "x" * 149)
    value(evaluate(client, tab, "JSON.stringify=()=> 'spoofed'; true"))
    check("page read ignores page-world JSON overrides", value(client.tool("page_read", {"tabId": tab}))["url"] == url + "/#different")
    value(client.tool("page_history", {"tabId": tab, "action": "reload"}))
    value(client.tool("page_wait", {"tabId": tab, "text": "MCP integration"}))
    check("large result returns an explicit error", evaluate(client, tab, "'🦊'.repeat(100000)")["result"]["isError"])
    check("JS exception is a tool error", evaluate(client, tab, "throw new Error('fixture')")["result"]["isError"])
    check("forbidden navigation", client.tool("page_navigate", {"tabId": tab, "url": "file:///etc/passwd"})["result"]["isError"])
    check("invalid tool arguments", "error" in client.tool("page_read", {"tabId": 42}))
    raw = socket.socket(socket.AF_UNIX)
    raw.settimeout(5)
    raw.connect(str(socket_path))
    raw.sendall(b"x" * (1_048_576 + 1))
    try:
        closed = raw.recv(1) == b""
    except ConnectionResetError:
        closed = True
    raw.close()
    check("oversized frame disconnects", closed)
    other = Client()
    check("concurrent client works", other.call("ping")["result"] == {})
    other.close()
    peers = [Client() for _ in range(7)]
    excess = subprocess.run([str(executable), "--mcp", str(socket_path)],
                            input=b'{"jsonrpc":"2.0","id":1,"method":"ping"}\n',
                            capture_output=True, timeout=5)
    check("ninth client is refused", not excess.stdout)
    for peer in peers:
        peer.close()
    check("existing client survives capacity limit", client.call("ping")["result"] == {})
    for _ in range(10):
        transient = Client()
        transient.close()
    check("repeated disconnects release client slots", client.call("ping")["result"] == {})
    slow = Client()
    started = time.monotonic()
    try:
        answer = evaluate(slow, tab, "new Promise(() => {})")
        timeout_observed = answer.get("result", {}).get("isError", False)
    except EOFError:
        timeout_observed = True
    check("unresolved page promise is bounded", timeout_observed and time.monotonic() - started < 28)
    check("other client survives page timeout", client.call("ping")["result"] == {})
    slow.close()
    client.close()
    client = Client()
    check("new client after timeout", client.call("ping")["result"] == {})
    process.kill()
    process.wait(timeout=10)
    eventually(lambda: client.proc.poll() is not None)
    check("browser crash disconnects client", True)
    launch(True)
    client = Client()
    check("restart recovers stale socket", client.call("ping")["result"] == {})
    client.close()
    quit_browser()
    check("clean shutdown removes socket", not socket_path.exists())
    launch(False)
    check("restart disabled stays unreachable", not socket_path.exists())
    quit_browser()
    (folder / "results.json").write_text(json.dumps(checks, indent=2))
    print("RESULTS " + str(folder / "results.json"), flush=True)
    if options.hold:
        launch(True)
        client = Client()
        existing = next((t for t in tabs(client) if t["url"].startswith(url + "/")), None)
        if existing:
            value(client.tool("page_navigate", {"tabId": existing["id"], "url": url + "/"}))
        else:
            command("cra://open?url=" + quote(url + "/", safe=""))
        eventually(lambda: any(t["url"] == url + "/" for t in tabs(client)))
        client.close()
        config = folder / "mcp.json"
        config.write_text(json.dumps({"mcpServers": {"cra": {"command": str(executable), "args": ["--mcp", str(socket_path)]}}}, indent=2))
        print("CLIENT_CONFIG " + str(config), flush=True)
        print("HOLDING for a real MCP client; Ctrl-C cleans up", flush=True)
        try:
            threading.Event().wait()
        except KeyboardInterrupt:
            print("Stopping isolated fixture", flush=True)
except Exception:
    print("DIAGNOSTICS " + str(folder), flush=True)
    try:
        diagnostic = Client()
        (folder / "input-events.json").write_text(json.dumps(evaluate(diagnostic, tab, "({events:window.inputEvents,visibility:document.visibilityState,focus:document.hasFocus()})"), indent=2))
        diagnostic.close()
    except Exception:
        pass
    raise
finally:
    for client in clients:
        if client.proc.poll() is None:
            client.proc.terminate()
            client.proc.wait(timeout=5)
    quit_browser()
    http.shutdown()
    log.close()
