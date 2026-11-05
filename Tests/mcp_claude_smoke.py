#!/usr/bin/env python3
"""Optional real-agent check on mcp_integration.py --hold's synthetic fixture."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("config", type=Path)
parser.add_argument("--claude", default=shutil.which("claude") or "claude")
options = parser.parse_args()
folder = Path(tempfile.mkdtemp(prefix="cra-claude-smoke-", dir="/tmp"))
names = {"tabs_list", "tab_open", "tab_show", "tab_close", "page_read", "page_snapshot", "page_navigate", "page_history", "page_wait", "page_screenshot", "page_pdf", "page_evaluate", "page_click", "page_hover", "page_scroll", "page_type", "page_fill", "page_press", "page_select", "page_drag", "page_upload", "page_download", "download_status", "download_cancel"}
allowed = ["mcp__cra__" + name for name in sorted(names)]
prompt = '''Test all 24 Cra MCP tools against the isolated synthetic local playground. These actions are authorized. Only localhost 127.0.0.1, no remote sites. Never use JavaScript to click, scroll, focus, select or change fields. All interactions must use the native input tools. Use tools sequentially on each tab, do not replay unconfirmed input.
1. tabs_list. Read the existing local playground using page_read, then tab_open a NEW tab at the same local origin /. Keep the original open. tab_show the new tab, page_wait for MCP integration, page_snapshot. Find the textbox ref whose label is Your name (possibly uppercase).
2. page_fill that ref with "Claude native". page_press End. page_type " ✓" into the same ref. page_hover #go then page_click #go.
3. page_select #choice value two. page_scroll #scroll-box dy 400. page_click #delay-button, page_wait for text Ready to continue.
4. page_evaluate ONLY this read-only check: ({nativeInputVerified:document.querySelector('#out').textContent==='Claude native ✓' && document.querySelector('#choice').value==='two' && document.querySelector('#scroll-box').scrollTop>0 && window.inputEvents.some(e=>e.type==='keydown'&&e.trusted) && window.inputEvents.some(e=>e.type==='click'&&e.trusted)}) . It must be true.
5. page_screenshot and page_pdf the same tab. Report the real returned path; do not invent it.
6. page_navigate to the same local origin /next?native-claude=1. page_wait for that exact URL; page_read. Then page_evaluate ONLY this read-only check: ({navigationVerified:location.pathname==='/next' && location.search==='?native-claude=1' && document.querySelector('h1').textContent==='MCP integration'}) . It must be true.
7. page_history back, page_wait for original /. tab_close only the new tab you opened. tab_show the original tab.
8. tab_open background=true at the same local origin /transfers. Poll tabs_list until loaded, then page_wait. page_fill #name with "Claude background 👋". page_drag #drag-source to targetSelector #drop-target. page_upload #upload with the exact PDF path returned in step 5.
9. page_evaluate only this read-only check: ({backgroundVerified:document.querySelector('#name').value==='Claude background 👋' && document.querySelector('#drag-result').textContent==='cra-native-card' && document.querySelector('#upload').files.length===1 && window.transferEvents.some(e=>e.type==='drop'&&e.trusted)}) . It must be true.
10. page_download in this background tab at the same local origin /download/sample.txt. Poll download_status with its returned downloadId until completed. Call download_cancel on that completed ID to verify it safely stays completed. tab_close the background tab.
Use ALL 24 tools at least once. Summarize actual results and any errors honestly.'''

command = [options.claude, "-p", prompt, "--strict-mcp-config", "--mcp-config", str(options.config.resolve()),
           "--tools", "", "--allowedTools", *allowed, "--setting-sources", "",
           "--settings", '{"disableAllHooks":true}', "--no-session-persistence",
           "--output-format", "stream-json", "--verbose", "--max-budget-usd", "5"]
with (folder / "events.jsonl").open("w") as output, (folder / "stderr.log").open("w") as error:
    completed = subprocess.run(command, cwd=folder, stdout=output, stderr=error, timeout=600)
print("RESULTS", folder, flush=True)
assert completed.returncode == 0, "Claude process failed; see diagnostics"
events = [json.loads(line) for line in (folder / "events.jsonl").read_text().splitlines()]
assert any(e.get("type") == "result" and not e.get("is_error") for e in events), "Claude did not complete successfully"
used = set()
verified = set()
responses = 0
for event in events:
    for block in event.get("message", {}).get("content", []):
        if not isinstance(block, dict):
            continue
        if block.get("type") == "tool_use":
            used.add(block["name"])
        elif block.get("type") == "tool_result":
            assert not block.get("is_error"), block
            responses += 1
            for item in block.get("content", []):
                if not isinstance(item, dict) or item.get("type") != "text":
                    continue
                try:
                    decoded = json.loads(item["text"])
                except ValueError:
                    continue
                if isinstance(decoded, dict):
                    value = decoded.get("result", {}).get("value", {})
                    if isinstance(value, dict):
                        verified.update(key for key in ("nativeInputVerified", "navigationVerified", "backgroundVerified") if value.get(key) is True)
assert set(allowed).issubset(used), "Missing tool calls: " + str(set(allowed) - used)
assert verified == {"nativeInputVerified", "navigationVerified", "backgroundVerified"}, "The page did not confirm both outcomes"
print("PASS Claude used all 24 tools;", responses, "successful responses; trusted native input and navigation confirmed")
