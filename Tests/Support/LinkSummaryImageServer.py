#!/usr/bin/env python3
"""Loopback HTTP proxy fixture; image URLs stay public .example names under real URL policy."""
import base64
import json
import socket
import select
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=')
condition = threading.Condition()
events = {}


def record(path, **values):
    with condition:
        events.setdefault(path, {}).update(values)
        condition.notify_all()


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_):
        pass

    def handle(self):
        try:
            super().handle()
        except (ConnectionResetError, BrokenPipeError):
            pass

    def do_CONNECT(self):
        record('CONNECT', hits=1, target=self.path)
        self.send_response(502)
        self.send_header('Content-Length', '0')
        self.end_headers()
        self.close_connection = True

    def do_GET(self):
        parsed = urlsplit(self.path)
        path, query = parsed.path, parse_qs(parsed.query)
        if path == '/wait':
            target, event = query['path'][0], query['event'][0]
            with condition:
                ready = condition.wait_for(lambda: events.get(target, {}).get(event), timeout=10)
                data = json.dumps({'ready': bool(ready), 'events': events}).encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path == '/stats':
            with condition:
                data = json.dumps(events).encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        with condition:
            count = events.get(path, {}).get('hits', 0) + 1
        record(path, hits=count, cookie=self.headers.get('Cookie', ''), started=True)
        if path == '/chain':
            number = int(query.get('n', ['0'])[0])
            self.send_response(302)
            self.send_header('Location', f'http://images.example/chain?n={number + 1}')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if path.startswith('/redirect') or path == '/cookie':
            destination = {
                '/redirect-private': f'http://127.0.0.1:{self.server.server_port}/forbidden',
                '/redirect-public': 'http://second.example/image',
                '/redirect-relative': '/image',
                '/redirect-credentials': 'http://user:pass@second.example/forbidden',
                '/redirect-file': 'file:///etc/hosts',
                '/redirect-loop': 'http://images.example/redirect-loop',
                '/redirect-hold': 'http://second.example/deadline-hold',
                '/cookie': 'http://images.example/image',
            }.get(path, 'http://second.example/image')
            self.send_response(302)
            self.send_header('Location', destination)
            if path == '/cookie':
                self.send_header('Set-Cookie', 'preview_fixture=must_not_send; Path=/')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        self.send_response(404 if path == '/status' else 200)
        self.send_header('Content-Type', 'text/plain' if path == '/mime' else 'image/png')
        if path == '/oversized-header':
            self.send_header('Content-Length', '4000001')
        elif path in ['/stream', '/cancel-hold', '/deadline-hold']:
            self.send_header('Transfer-Encoding', 'chunked')
        elif path == '/boundary':
            self.send_header('Content-Length', '4000000')
        else:
            self.send_header('Content-Length', str(len(PNG)))
        self.end_headers()
        if path == '/oversized-header':
            self.connection.settimeout(10)
            try:
                record(path, disconnected=self.connection.recv(1) == b'')
            except socket.timeout:
                record(path, stalled=True)
            except OSError:
                record(path, disconnected=True)
            return
        if path in ['/cancel-hold', '/deadline-hold']:
            try:
                self.wfile.write(b'1\r\nx\r\n')
                self.wfile.flush()
                record(path, body=True)
                # Heartbeats keep the session's idle timeout from masquerading as cancellation.
                # A broken implementation completes this finite fixture after ten seconds.
                for _ in range(50):
                    if select.select([self.connection], [], [], 0.2)[0]:
                        record(path, disconnected=self.connection.recv(1) == b'')
                        return
                    self.wfile.write(b'1\r\ny\r\n')
                    self.wfile.flush()
                self.wfile.write(b'0\r\n\r\n')
                self.wfile.flush()
                record(path, completed=True)
            except OSError:
                record(path, disconnected=True)
            return
        if path == '/stream':
            self.connection.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4096)
            chunk, sent = b'x' * 65536, 0
            try:
                for _ in range(192):
                    self.wfile.write(f'{len(chunk):x}\r\n'.encode() + chunk + b'\r\n')
                    self.wfile.flush()
                    sent += len(chunk)
                    record(path, bytes=sent)
                self.wfile.write(b'0\r\n\r\n')
                self.wfile.flush()
                record(path, completed=True)
            except OSError:
                record(path, bytes=sent, disconnected=True)
            return
        try:
            self.wfile.write(PNG + b'0' * (4000000 - len(PNG)) if path == '/boundary' else PNG)
        except OSError:
            pass


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
server.daemon_threads = True
print(server.server_port, flush=True)
server.serve_forever()
