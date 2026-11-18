#!/usr/bin/env python3
"""Local synthetic fixtures for CraUITests: POST/opener pages (PopupTests) and a passkey page
(PasskeyTests). No external requests."""
import argparse
import html
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


class PopupHandler(BaseHTTPRequestHandler):
    def page(self, body, cookie=None):
        encoded = ('<!doctype html><meta name="viewport" content="width=device-width">'
                   '<style>body{font:20px -apple-system;padding:24px}button{font-size:20px;padding:14px}</style>'
                   + body).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(encoded)))
        self.send_header('Cache-Control', 'no-store')
        if cookie:
            self.send_header('Set-Cookie', cookie)
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        url = urlsplit(self.path)
        if url.path == '/source':
            private = parse_qs(url.query).get('private') == ['1']
            mode = 'private' if private else 'normal'
            title = 'Private Popup Source' if private else 'Popup Source'
            normal_cookie = 'normalSession=normal' in self.headers.get('Cookie', '')
            cookie_state = 'Normal cookie present' if normal_cookie else 'Normal cookie absent'
            # The form explicitly opts into an opener; ordinary noopener links keep WebKit's policy.
            self.page(f'''<title>{title}</title><h1>{title}</h1><p>{cookie_state}</p>
<form method="POST" target="_blank" rel="opener" action="/checkout">
<input type="hidden" name="order" value="synthetic-123"><input type="hidden" name="mode" value="{mode}">
<button>Post to popup</button></form><p id="reply">No popup reply</p>
<button onclick="openBlank()">Open blank popup</button>
<script>
addEventListener('message', event => {{
  if (event.origin === location.origin && event.data === 'synthetic-popup-reply')
    document.getElementById('reply').textContent = 'Popup reply received';
}});
function openBlank() {{
  const child = window.open('about:blank', '_blank');
  if (!child) {{ document.getElementById('reply').textContent = 'Popup handle missing'; return; }}
  child.document.write('<title>Blank Popup</title><h1>Blank Popup</h1><p>' +
    (child.opener === window ? 'Opener handle preserved' : 'Opener handle missing') + '</p>' +
    '<button onclick="window.opener.postMessage(\\\'synthetic-popup-reply\\\',window.opener.location.origin);window.close()">Reply and close</button>');
  child.document.close();
}}
</script>''', cookie=f'sourceSession={mode}; Path=/' if private else 'normalSession=normal; Path=/')
        elif url.path == '/passkey':
            # WebAuthn needs a secure context and a domain as its relying party: the test opens this
            # page as http://localhost:<port>, which is both (127.0.0.1 isn't a valid RP ID).
            self.page('''<title>Passkey Fixture</title><h1>Passkey Fixture</h1>
<button onclick="createPasskey()">Create passkey</button><p id="answer">No passkey answer</p>
<script>
// Without the browser entitlement WebKit refuses at once; with it the request waits on iOS's
// passkey sheet, which the page can't see, so it says so once the request has stayed open.
function createPasskey() {
  const answer = document.getElementById('answer');
  let answered = false;
  setTimeout(() => { if (!answered) answer.textContent = 'Passkey request still open'; }, 3000);
  navigator.credentials.create({publicKey: {
    rp: {name: 'Cra fixture', id: location.hostname},
    user: {id: new Uint8Array(16), name: 'fixture@cra.test', displayName: 'Fixture'},
    challenge: new Uint8Array(32), pubKeyCredParams: [{type: 'public-key', alg: -7}],
    authenticatorSelection: {residentKey: 'required'}, timeout: 60000}})
    .then(() => { answered = true; answer.textContent = 'Passkey created'; },
          error => { answered = true; answer.textContent = 'Passkey refused: ' + error.name; });
}
</script>''')
        elif url.path == '/checkout':
            self.page('<title>POST lost</title><h1>POST lost</h1><p>Unexpected GET</p>')
        else:
            self.send_error(404)

    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        if urlsplit(self.path).path != '/checkout' or not 0 < length <= 4096:
            self.send_error(400)
            return
        body = self.rfile.read(length).decode('utf-8')
        fields = parse_qs(body)
        mode = fields.get('mode', [''])[0]
        valid = fields.get('order') == ['synthetic-123'] and mode in ('normal', 'private')
        title = 'POST preserved' if valid else 'POST body lost'
        cookies = self.headers.get('Cookie', '')
        shared = ('sourceSession=private' if mode == 'private' else 'normalSession=normal') in cookies
        self.page(f'''<title>{title}</title><h1>{title}</h1><p>Body: {html.escape(body)}</p>
<p>{'Source cookie shared' if shared else 'Source cookie lost'}</p><p id="opener"></p>
<button onclick="if(window.opener)window.opener.postMessage('synthetic-popup-reply',location.origin);window.close()">Reply and close</button>
<script>document.getElementById('opener').textContent = window.opener ? 'Opener available' : 'Opener missing';</script>''')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=18765)
    options = parser.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', options.port), PopupHandler)
    print(f'Popup fixtures: http://127.0.0.1:{server.server_port}/source', flush=True)
    server.serve_forever()
