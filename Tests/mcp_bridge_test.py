"""Exercise the production stdio bridge against a local Unix peer, without Chromium."""
import json
import pathlib
import socket
import subprocess
import sys
import tempfile
import threading

with tempfile.TemporaryDirectory(prefix="cra-mcp-wire-", dir="/tmp") as folder:
    path = str(pathlib.Path(folder) / "socket")
    listener = socket.socket(socket.AF_UNIX)
    listener.bind(path)
    listener.listen()
    failures = []

    def serve():
        try:
            peer, _ = listener.accept()
            with peer, peer.makefile("rb") as reader:
                for line in reader:
                    request = json.loads(line)
                    peer.sendall(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": {}}).encode() + b"\n")
        except Exception as error:
            failures.append(error)

    worker = threading.Thread(target=serve, daemon=True)
    worker.start()
    payload = b"".join(json.dumps({"jsonrpc": "2.0", "id": i, "method": "ping"}).encode() + b"\n" for i in range(20))
    result = subprocess.run([sys.argv[1], "--mcp", path], input=payload, capture_output=True, timeout=15)
    assert result.returncode == 0, result.stderr
    assert [json.loads(line)["id"] for line in result.stdout.splitlines()] == list(range(20))
    worker.join(timeout=5)
    assert not worker.is_alive() and not failures, failures
    listener.close()
    missing = subprocess.run([sys.argv[1], "--mcp", path + "-missing"], input=b"", capture_output=True, timeout=5)
    assert missing.returncode != 0 and not missing.stdout and missing.stderr
print("MCP bridge: 20 pipelined requests drain at EOF; unavailable server fails on stderr")
