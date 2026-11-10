#!/usr/bin/env python3
"""Real-app MCP regressions with a temporary profile and localhost; briefly opens visible PiP."""
import argparse
import http.server
import json
import os
from pathlib import Path
import plistlib
import re
import select
import socket
import subprocess
import tempfile
import threading
import time
import uuid
from urllib.parse import quote

parser = argparse.ArgumentParser()
parser.add_argument("--app", default="build/CraDev.app")
parser.add_argument("--pause-before-input", action="store_true", help="Wait for a start-input file after focusing the test window.")
parser.add_argument("--hold", action="store_true", help="Keep the isolated instance for a real MCP client; Ctrl-C cleans up.")
parser.add_argument("--with-pip", action="store_true", help="Also check Document PiP, which floats a window over the screen.")
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

uploaded = {}
download_cookies = []
delayed_requests = 0
class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        seen_paths.add(self.path)
        global delayed_requests
        delayed_body = None
        if self.path == '/download/no-headers':
            time.sleep(70)
            return
        if self.path.startswith('/download/delayed'):
            delayed_requests += 1
            delayed_body = str(delayed_requests).encode()
            time.sleep(.4)
        if self.path.startswith('/download/'):
            download_cookies.append(self.headers.get('Cookie', ''))
            if self.path == '/download/redirect':
                self.send_response(302); self.send_header('Location', '/download/auth.txt'); self.end_headers(); return
            if 'mcp_fixture=session' not in self.headers.get('Cookie', ''):
                self.send_response(403); self.end_headers(); return
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Disposition', 'attachment; filename="../../escape.txt"')
            self.send_header('Content-Length', '67108865' if self.path.endswith('/oversize') else '1048576' if self.path.endswith('/slow') else str(len(delayed_body)) if delayed_body else '25')
            self.end_headers()
            try:
                if self.path.endswith('/slow'):
                    for _ in range(1024): self.wfile.write(b'x'*1024); self.wfile.flush(); time.sleep(.03)
                elif self.path.endswith('/oversize'): self.wfile.write(b'x')
                else: self.wfile.write(delayed_body if delayed_body else b'Cra authenticated sample\n')
            except (BrokenPipeError, ConnectionResetError): pass
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        if self.path == '/normal': self.send_header('Set-Cookie', 'mcp_fixture=session; Path=/; HttpOnly; SameSite=Strict')
        self.end_headers()
        try: self.wfile.write((Path(__file__).parent / 'Fixtures/MCP/transfers.html').read_bytes())
        except (BrokenPipeError, ConnectionResetError): pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        uploaded[self.path] = body
        self.send_response(200); self.end_headers(); self.wfile.write(b'Received '+str(len(body)).encode()+b' bytes')
    def log_message(self, *args): pass

http = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
threading.Thread(target=http.serve_forever, daemon=True).start()
url = "http://127.0.0.1:" + str(http.server_port)

def command(value):
    with commands.open("a") as file:
        file.write(value + "\n")

def launch(enabled):
    global process
    environment = dict(os.environ, CRA_DATA_DIR=str(profile), CRA_COMMAND_FILE=str(commands), CRA_TEST_BACKGROUND="1")
    process = subprocess.Popen([str(executable), "-mcpEnabled", "YES" if enabled else "NO", "-mcpApprovesAgents", "YES", "-mcpAllowsScripts", "YES"],
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

def js(client, tab, expression):
    return value(evaluate(client, tab, expression))["result"].get("value")

def fail(name, response):
    check(name, bool(response.get('error') or response.get('result',{}).get('isError')))

def ready(client, tab):
    eventually(lambda: next((t for t in tabs(client) if t['id']==tab and t['loaded']), None))
    value(client.tool('page_wait', {'tabId':tab}))

def terminal(client, tab, identifier):
    def result():
        state=value(client.tool('download_status',{'tabId':tab,'downloadId':identifier}))
        return state if state['status']!='in_progress' else None
    return eventually(result)

def live_count():
    offset=(folder/'browser.log').stat().st_size
    command('cra://debug?windows=1')
    def count():
        entries=re.findall(r'Cra windows: liveBrowsers=(\d+)',(folder/'browser.log').read_text(errors='replace')[offset:])
        return int(entries[-1]) if entries else None
    return eventually(count)

def settled(client,tab,identifier):
    return eventually(lambda: value(client.tool('download_status',{'tabId':tab,'downloadId':identifier})).get('canStartNext'))

try:
    root=profile/'mcp-transfers';root.mkdir(mode=0o700)
    orphan=root/('upload-'+str(uuid.uuid4()));orphan.mkdir(mode=0o700);(orphan/'synthetic.txt').write_text('discard')
    retained=root/('download-'+str(uuid.uuid4()));retained.mkdir(mode=0o700);(retained/'download').write_text('keep')
    preferences=profile/'Chromium/Default/Preferences'
    preferences.parent.mkdir(parents=True,exist_ok=True)
    permission_history={'Notifications':{'ignore_count':2},'Geolocation':{'dismiss_count':1}}
    preferences.write_text(json.dumps({'profile':{'content_settings':{'exceptions':{'permission_autoblocking_data':{url+',*':{'setting':permission_history}}}}}}))
    launch(True)
    check('restart removes orphan uploads but keeps completed exports',not orphan.exists() and (retained/'download').read_text()=='keep')
    client=Client()
    command('cra://open?url='+quote(url+'/normal',safe=''))
    normal=eventually(lambda: next((t['id'] for t in tabs(client) if t['url']==url+'/normal'),None))
    ready(client,normal)
    baseline=live_count()
    check('26 tools advertised',len(client.call('tools/list')['result']['tools'])==26)
    agent=value(client.tool('tab_open',{'url':url+'/agent','windowless':True}))['tabId']
    ready(client,agent)
    eventually(lambda:live_count()==baseline+1)
    check('agent tab has visible rendering without a window', js(client,agent,'document.visibilityState')=='visible')
    check('windowless viewport is 1280x800',js(client,agent,'[innerWidth,innerHeight]')==[1280,800])
    result=value(client.tool('page_fill',{'tabId':agent,'selector':'#name','text':'Unsichtbar 👋 Ä'}))
    check('windowless Unicode input is trusted', result['trustedEvents']['keydown']==result['trustedEvents']['keyup'] and js(client,agent,'document.querySelector("#name").value')=='Unsichtbar 👋 Ä')
    check('background input does not alter foreground page',js(client,normal,'document.querySelector("#name").value')=='')
    screenshot=client.tool('page_screenshot',{'tabId':agent})
    check('windowless screenshot',screenshot['result']['content'][0]['type']=='image')
    import base64
    (folder/'agent.jpg').write_bytes(base64.b64decode(screenshot['result']['content'][0]['data']))
    second=Client()
    check('agent tabs are connection-private',agent not in [t['id'] for t in tabs(second)])
    fail('other client cannot read agent tab',second.tool('page_read',{'tabId':agent}))
    fail('background tab cannot unexpectedly appear',client.tool('tab_show',{'tabId':agent}))
    result=value(client.tool('page_drag',{'tabId':agent,'selector':'#drag-source','targetSelector':'#drop-target'}))
    check('HTML drag delivered trusted drop and payload',result['kind']=='html' and result['trustedEvents']['drop']>0 and js(client,agent,'document.querySelector("#drag-result").textContent')=='cra-native-card')
    result=value(client.tool('page_drag',{'tabId':agent,'selector':'#pointer-source','targetSelector':'#pointer-target'}))
    check('pointer drag with native pointer capture',result['kind']=='pointer' and js(client,agent,'document.querySelector("#pointer-result").textContent').startswith('Released '))
    fail('ambiguous drag source refused',client.tool('page_drag',{'tabId':agent,'selector':'.card','targetSelector':'#drop-target'}))
    fail('absent drop target refused',client.tool('page_drag',{'tabId':agent,'selector':'#drag-source','targetSelector':'#absent'}))
    files=[folder/'sample.txt',folder/'other.txt']
    files[0].write_bytes(b'Native upload: '+bytes(range(32)))
    files[1].write_bytes('Grüsse 👋'.encode())
    for _ in range(17):
        response=client.tool('page_upload',{'tabId':agent,'selector':'#name','paths':[str(files[0])]})
        assert response['result'].get('isError')
    check('invalid targets do not consume upload quota',not list((profile/'mcp-transfers').glob('upload-*')))
    for _ in range(17):
        rejected=value(client.tool('tab_open',{'url':url+'/rejected'}))['tabId'];ready(client,rejected)
        assert client.tool('page_upload',{'tabId':rejected,'selector':'#name','paths':[str(files[0])]} )['result'].get('isError')
        # Leave the tab open: cleanup must follow validation, not rely on closing a tab.
    value(client.tool('tab_show',{'tabId':normal}))
    for _ in range(17):
        assert client.tool('download_status',{'tabId':normal,'downloadId':'invalid'})['result'].get('isError')
    result=value(client.tool('page_upload',{'tabId':agent,'selector':'#upload','paths':[str(f) for f in files]}))
    check('rejected uploads across 17 normal tabs leave transfer capacity available',len(result['files'])==2)
    check('multiple native file selection',len(result['files'])==2 and result['trustedEvents']['change']>0)
    value(client.tool('page_click',{'tabId':agent,'selector':'#send-files'}))
    eventually(lambda:len(uploaded)==2)
    check('uploaded bytes reach HTTP server exactly',uploaded['/upload/sample.txt']==files[0].read_bytes() and uploaded['/upload/other.txt']==files[1].read_bytes())
    # Wait for actual off-main staging, then cancel before Chromium selection.
    large=folder/'staging-cancel.bin'
    with large.open('wb') as output_file: output_file.truncate(16*1024*1024)
    for attempt in range(17):
        before=set((profile/'mcp-transfers').glob('upload-*'))
        client.next_id+=1;request_id=client.next_id
        request={'jsonrpc':'2.0','id':request_id,'method':'tools/call','params':{'name':'page_upload','arguments':{'tabId':agent,'selector':'#upload','paths':[str(large)]*4}}}
        client.proc.stdin.write(json.dumps(request).encode()+b'\n');client.proc.stdin.flush()
        deadline=time.monotonic()+5
        while not (set((profile/'mcp-transfers').glob('upload-*'))-before):
            assert time.monotonic()<deadline,'staging did not start'
            assert not select.select([client.proc.stdout],[],[],0)[0],'upload finished before staging cancellation'
            time.sleep(.001)
        client.proc.stdin.write(json.dumps({'jsonrpc':'2.0','method':'notifications/cancelled','params':{'requestId':request_id}}).encode()+b'\n');client.proc.stdin.flush()
        assert select.select([client.proc.stdout],[],[],15)[0]
        response=json.loads(client.proc.stdout.readline())
        assert response['id']==request_id and response['result'].get('isError'),response
        eventually(lambda:set((profile/'mcp-transfers').glob('upload-*'))==before)
    check('17 cancellations during real staging release files and quota',True)
    value(client.tool('page_upload',{'tabId':agent,'selector':'#hidden-upload','paths':[str(files[0])]}))
    check('hidden file input uses native selection',js(client,agent,'document.querySelector("#hidden-upload").files[0].name')=='sample.txt')
    fail('single input refuses multiple files',client.tool('page_upload',{'tabId':agent,'selector':'#hidden-upload','paths':[str(f) for f in files]}))
    fail('disabled file input refused',client.tool('page_upload',{'tabId':agent,'selector':'#disabled-upload','paths':[str(files[0])]}))
    link=folder/'symlink.txt';link.symlink_to(files[0])
    fail('upload symlink refused',client.tool('page_upload',{'tabId':agent,'selector':'#upload','paths':[str(link)]}))
    fail('upload directory refused',client.tool('page_upload',{'tabId':agent,'selector':'#upload','paths':[str(folder)]}))
    fail('upload relative path refused',client.tool('page_upload',{'tabId':agent,'selector':'#upload','paths':['sample.txt']}))
    huge=folder/'huge.bin'
    with huge.open('wb') as file: file.truncate(16*1024*1024+1)
    fail('oversize upload refused',client.tool('page_upload',{'tabId':agent,'selector':'#upload','paths':[str(huge)]}))
    fail('downloads cannot redirect user tab downloads',client.tool('page_download',{'tabId':normal,'url':url+'/download/auth.txt'}))
    started=value(client.tool('page_download',{'tabId':agent,'url':url+'/download/redirect'}))
    check('download starts asynchronously',started['status']=='in_progress' and 'path' not in started)
    done=terminal(client,agent,started['downloadId'])
    check('download follows redirect and shares HttpOnly session',done['status']=='completed' and all('mcp_fixture=session' in c for c in download_cookies))
    output=Path(done['path'])
    check('download content exact',output.read_bytes()==b'Cra authenticated sample\n')
    check('download filename cannot escape private directory',output.name=='download' and output.is_relative_to(profile/'mcp-transfers'))
    check('download file and folder are private',output.stat().st_mode&0o777==0o600 and output.parent.stat().st_mode&0o777==0o700)
    fail('foreign download ID refused',client.tool('download_status',{'tabId':agent,'downloadId':'00000000-0000-0000-0000-000000000000'}))
    slow=value(client.tool('page_download',{'tabId':agent,'url':url+'/download/slow'}))
    eventually(lambda:value(client.tool('download_status',{'tabId':agent,'downloadId':slow['downloadId']}))['receivedBytes']>0)
    fail('overlapping download refused',client.tool('page_download',{'tabId':agent,'url':url+'/download/auth.txt'}))
    cancel=value(client.tool('download_cancel',{'tabId':agent,'downloadId':slow['downloadId']}))
    check('download cancellation returns terminal state',cancel['status']=='cancelled' and 'path' not in cancel)
    settled(client,agent,slow['downloadId'])
    check('cancelled partial files removed', not any(p.name.endswith('.crdownload') for p in (profile/'mcp-transfers').rglob('*')))
    big=value(client.tool('page_download',{'tabId':agent,'url':url+'/download/oversize'}))
    big=terminal(client,agent,big['downloadId'])
    check('oversize download refused',big['status'] in ['cancelled','failed'] and 'path' not in big)
    settled(client,agent,big['downloadId'])
    canonical=value(client.tool('page_download',{'tabId':agent,'url':url.replace('http:','HTTP:')+'/download/auth.txt'}))
    canonical=terminal(client,agent,canonical['downloadId'])
    check('canonicalized uppercase scheme downloads',canonical['status']=='completed')
    # A syntactically valid origin without slash must match Chromium's canonical URL.
    root=value(client.tool('page_download',{'tabId':agent,'url':url}))
    root=terminal(client,agent,root['downloadId'])
    check('origin-only download URL canonicalization',root['status']=='completed')
    value(client.tool('page_click',{'tabId':agent,'selector':'#alert'}))
    check('agent JavaScript dialog suppressed without blocking',js(client,agent,'document.querySelector("#dialog-result").textContent')=='Alert dismissed')
    value(client.tool('page_click',{'tabId':agent,'selector':'#upload'}))
    check('native file chooser cancelled in agent tab',bool(client.call('ping').get('result')=={}))
    check('notification permission initially unset',js(client,normal,'Notification.permission')=='default')
    for attempt in range(6):
        value(client.tool('page_click',{'tabId':agent,'selector':'#permission'}))
        eventually(lambda:js(client,agent,'window.permissionRequests')==attempt+1)
        check('agent prompt '+str(attempt+1)+' ignored without a profile embargo',js(client,agent,'document.querySelector("#permission-result").textContent')=='default' and js(client,normal,'Notification.permission')=='default')
    agent_staged=set((profile/'mcp-transfers').glob('*/*/*'))
    # Verify ordinary visible tabs support the same native file/drag tools.
    value(client.tool('tab_show',{'tabId':normal}))
    value(client.tool('page_drag',{'tabId':normal,'selector':'#drag-source','targetSelector':'#drop-target'}))
    value(client.tool('page_upload',{'tabId':normal,'selector':'#upload','paths':[str(files[0])]}))
    check('normal tab native drag and upload',js(client,normal,'document.querySelector("#drag-result").textContent')=='cra-native-card' and js(client,normal,'document.querySelector("#upload").files.length')==1)
    for attempt in range(6):
        value(client.tool('page_click',{'tabId':agent,'selector':'#permission-navigate'}))
        ready(client,agent)
        check('permission navigation '+str(attempt+1)+' leaves the normal profile unblocked',js(client,normal,'Notification.permission')=='default')
    staged=[p for p in agent_staged if p.is_file()]
    check('upload copies have private permissions',bool(staged) and all(p.stat().st_mode&0o777==0o600 for p in staged))
    baseline=live_count()-1
    value(client.tool('tab_close',{'tabId':agent}))
    eventually(lambda:live_count()==baseline)
    eventually(lambda:all(not p.exists() for p in staged))
    check('closing agent removes staged upload files',True)
    check('completed download persists after close',output.exists())
    # Document PiP intentionally has no CraBrowser owner. Keep it alive, while the
    # immediate-close tests below must still reclaim tabs whose weak owner vanished.
    # PiP floats over every app, so it runs only when asked (--with-pip).
    def pip_checks(baseline):
        value(client.tool('tab_show',{'tabId':normal}))
        tab_ids={t['id'] for t in tabs(client)}
        value(client.tool('page_click',{'tabId':normal,'selector':'#document-pip'}))
        eventually(lambda:js(client,normal,'!!window.testPiP && !testPiP.closed'))
        eventually(lambda:live_count()==baseline+1)
        check('Document PiP stays alive without a sidebar tab',
              {t['id'] for t in tabs(client)}==tab_ids and
              js(client,normal,'testPiP.document.body.textContent')=='Cra Document PiP fixture')
        js(client,normal,'testPiP.close()')
        eventually(lambda:live_count()==baseline)
        check('closing Document PiP releases its browser',js(client,normal,'testPiP.closed'))
        value(client.tool('tab_show',{'tabId':normal}))
        value(client.tool('page_click',{'tabId':normal,'selector':'#document-pip'}))
        eventually(lambda:js(client,normal,'!!window.testPiP && !testPiP.closed'))
        eventually(lambda:live_count()==baseline+1)
        value(client.tool('page_navigate',{'tabId':normal,'url':url+'/normal?pip-cleanup'}))
        ready(client,normal)
        eventually(lambda:live_count()==baseline)
        check('navigating the opener closes Document PiP',js(client,normal,'!window.testPiP'))
    if options.with_pip: pip_checks(baseline)
    # Immediate close races asynchronous CEF creation; no orphan agent pages may remain.
    for _ in range(8):
        quick=value(client.tool('tab_open',{'url':url+'/quick','windowless':True}))['tabId']
        value(client.tool('tab_close',{'tabId':quick}))
    eventually(lambda:live_count()==baseline)
    check('immediate agent open/close leaves no CEF browsers',True)
    # Delayed response headers exercise native cancellation before an ID is known.
    delayed=value(client.tool('tab_open',{'url':url+'/agent','windowless':True}))['tabId'];ready(client,delayed)
    first=value(client.tool('page_download',{'tabId':delayed,'url':url+'/download/delayed'}))
    eventually(lambda:delayed_requests>0)
    value(client.tool('download_cancel',{'tabId':delayed,'downloadId':first['downloadId']}))
    settled(client,delayed,first['downloadId'])
    previous=delayed_requests
    next_download=value(client.tool('page_download',{'tabId':delayed,'url':url+'/download/delayed'}))
    done_next=terminal(client,delayed,next_download['downloadId'])
    check('cancelled request cannot replace next same-URL download',done_next['status']=='completed' and Path(done_next['path']).read_text()==str(previous+1))
    value(client.tool('tab_close',{'tabId':delayed}))
    downloads_before=set((Path.home()/'Downloads').glob('*'))
    for i in range(8):
        closing=value(client.tool('tab_open',{'url':url+'/agent','windowless':True}))['tabId'];ready(client,closing)
        value(client.tool('page_download',{'tabId':closing,'url':url+'/download/delayed?close='+str(i)}))
        value(client.tool('tab_close',{'tabId':closing}))
    eventually(lambda:live_count()==baseline)
    time.sleep(.6)
    check('late download callbacks never escape to user Downloads',set((Path.home()/'Downloads').glob('*'))==downloads_before)
    check('closing pending downloads leaves no CEF browsers',live_count()==baseline)
    abandoned=value(client.tool('tab_open',{'url':url+'/abandoned','windowless':True}))['tabId'];ready(client,abandoned)
    client.close()
    eventually(lambda:live_count()==baseline)
    check('disconnect cleans up connection-owned agents',True)
    timeout_client=Client()
    waiting=value(timeout_client.tool('tab_open',{'url':url+'/agent','windowless':True}))['tabId'];ready(timeout_client,waiting)
    stalled=value(timeout_client.tool('page_download',{'tabId':waiting,'url':url+'/download/no-headers'}))
    def timed_out():
        state=value(timeout_client.tool('download_status',{'tabId':waiting,'downloadId':stalled['downloadId']}))
        return state if state['status']=='timed_out' else None
    done=eventually(timed_out,timeout=65)
    check('missing headers timeout explains slot cleanup', 'tab_close' in done.get('recovery','') and not done['canStartNext'])
    eventually(lambda:any(t['id']==waiting and t.get('closed') for t in tabs(timeout_client)))
    check('timed-out tab remains discoverable for cleanup',True)
    eventually(lambda:live_count()==baseline)
    value(timeout_client.tool('tab_close',{'tabId':waiting}))
    replacement=value(timeout_client.tool('tab_open',{'url':url+'/agent','windowless':True}))['tabId'];ready(timeout_client,replacement)
    retry=value(timeout_client.tool('page_download',{'tabId':replacement,'url':url+'/download/auth.txt'}))
    check('new agent can download after a stalled request',terminal(timeout_client,replacement,retry['downloadId'])['status']=='completed')
    timeout_client.close()
    eventually(lambda:live_count()==baseline)
    quit_browser()
    saved=json.loads(preferences.read_text())['profile']['content_settings']['exceptions']['permission_autoblocking_data'][url+',*']['setting']
    check('agent prompts preserve existing user permission history on disk',saved==permission_history)
    print('ALL',len(checks),'CHECKS PASSED',flush=True)
finally:
    (folder/'results.json').write_text(json.dumps({'checks':checks},indent=2))
    for client in clients: client.close()
    quit_browser();http.shutdown()
    print('ARTIFACT',folder,flush=True)
