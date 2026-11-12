# server.py <dir> <port, 0 for any> <marks file>: serves the bench page and appends each POST's JSON
# (the page's paint and visibility marks) with its arrival time to the marks file. Prints its port.
import functools, http.server, json, socketserver, sys, time
class Server(http.server.ThreadingHTTPServer):
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = "127.0.0.1", self.server_address[1]
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        with open(sys.argv[3], "a") as f: f.write(json.dumps({"recv": time.time() * 1000, **json.loads(body)}) + "\n")
        self.send_response(204); self.end_headers()
s = Server(("127.0.0.1", int(sys.argv[2])), functools.partial(H, directory=sys.argv[1]))
print(s.server_address[1], flush=True)
s.serve_forever()
