#!/usr/bin/env python3
"""Independent MCP SDK interoperability journey against the held synthetic playground."""
import asyncio
from datetime import timedelta
import importlib.metadata
import json
from pathlib import Path
import sys
from urllib.parse import urlsplit

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

TOOLS = {"tabs_list", "tab_open", "tab_show", "tab_close", "page_read", "page_snapshot", "page_navigate",
         "page_history", "page_wait", "page_screenshot", "page_pdf", "page_evaluate", "page_click", "page_hover",
         "page_scroll", "page_type", "page_fill", "page_press", "page_select", "page_drag", "page_upload", "page_download", "download_status", "download_cancel"}

async def main():
    config = json.loads(Path(sys.argv[1]).read_text())["mcpServers"]["cra"]
    async with stdio_client(StdioServerParameters(**config)) as streams:
        async with ClientSession(*streams, read_timeout_seconds=timedelta(seconds=125)) as client:
            initialized = await client.initialize()
            print("PASS SDK", importlib.metadata.version("mcp"), "handshake", initialized.protocolVersion, flush=True)
            tools = await client.list_tools()
            assert {tool.name for tool in tools.tools} == TOOLS
            used = set()

            async def call(name, arguments=None):
                result = await client.call_tool(name, arguments or {})
                assert not result.isError, result
                used.add(name)
                if name == "page_screenshot":
                    assert result.content[0].type == "image" and result.content[0].mimeType == "image/jpeg"
                    return result
                return json.loads(result.content[0].text)

            tabs = await call("tabs_list")
            existing = next(t for t in tabs if urlsplit(t["url"]).hostname == "127.0.0.1")
            origin = urlsplit(existing["url"])
            base = origin.scheme + "://" + origin.netloc
            tab = (await call("tab_open", {"url": base + "/"}))["tabId"]
            async with asyncio.timeout(15):
                while not any(t["id"] == tab and t["loaded"] for t in await call("tabs_list")):
                    await asyncio.sleep(.1)
            await call("tab_show", {"tabId": tab})
            await call("page_wait", {"tabId": tab, "url": base + "/", "text": "MCP integration"})
            assert "MCP integration" in (await call("page_read", {"tabId": tab}))["text"]
            snap = await call("page_snapshot", {"tabId": tab})
            ref = next(e["ref"] for e in snap["elements"] if e["role"] == "textbox" and e["name"].casefold() == "your name")
            await call("page_fill", {"tabId": tab, "ref": ref, "text": "SDK 👨‍👩‍👧‍👦"})
            await call("page_press", {"tabId": tab, "key": "End"})
            await call("page_type", {"tabId": tab, "ref": ref, "text": " ✓"})
            await call("page_hover", {"tabId": tab, "selector": "#go"})
            await call("page_click", {"tabId": tab, "selector": "#go"})
            result = await call("page_evaluate", {"tabId": tab, "expression": "({output:document.querySelector('#out').textContent,session:document.cookie.includes('mcp_fixture=session')})"})
            assert result["result"]["value"] == {"output": "SDK 👨‍👩‍👧‍👦 ✓", "session": True}
            await call("page_select", {"tabId": tab, "selector": "#choice", "value": "three"})
            await call("page_scroll", {"tabId": tab, "selector": "#scroll-box", "dy": 400})
            await call("page_screenshot", {"tabId": tab})
            pdf = await call("page_pdf", {"tabId": tab})
            assert Path(pdf["path"]).read_bytes().startswith(b"%PDF-")
            await call("page_navigate", {"tabId": tab, "url": base + "/next?sdk=1"})
            await call("page_wait", {"tabId": tab, "url": base + "/next?sdk=1"})
            await call("page_history", {"tabId": tab, "action": "back"})
            await call("page_wait", {"tabId": tab, "url": base + "/"})
            await call("tab_close", {"tabId": tab})
            await call("tab_show", {"tabId": existing["id"]})
            agent = (await call("tab_open", {"url": base + "/transfers", "background": True}))["tabId"]
            async with asyncio.timeout(15):
                while not any(t["id"] == agent and t["loaded"] for t in await call("tabs_list")):
                    await asyncio.sleep(.1)
            await call("page_wait", {"tabId": agent})
            await call("page_fill", {"tabId": agent, "selector": "#name", "text": "SDK background 👋"})
            drag = await call("page_drag", {"tabId": agent, "selector": "#drag-source", "targetSelector": "#drop-target"})
            assert drag["kind"] == "html" and drag["trustedEvents"]["drop"] > 0
            upload = await call("page_upload", {"tabId": agent, "selector": "#upload", "paths": [pdf["path"]]})
            assert upload["files"][0]["size"] == Path(pdf["path"]).stat().st_size
            download = await call("page_download", {"tabId": agent, "url": base + "/download/sample.txt"})
            async with asyncio.timeout(15):
                while download["status"] == "in_progress":
                    await asyncio.sleep(.1)
                    download = await call("download_status", {"tabId": agent, "downloadId": download["downloadId"]})
            assert download["status"] == "completed" and Path(download["path"]).read_text().startswith("Cra playground:")
            cancelled = await call("download_cancel", {"tabId": agent, "downloadId": download["downloadId"]})
            assert cancelled["status"] == "completed"
            await call("tab_close", {"tabId": agent})
            assert used == TOOLS, TOOLS - used
            print("PASS SDK all 24 tools, stable refs, native Unicode input, session, image/PDF and owned-tab lifecycle", flush=True)

asyncio.run(main())
