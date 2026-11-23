#!/usr/bin/env python3
"""Local synthetic fixtures for CraUITests: POST/opener pages (PopupTests), a passkey page
(PasskeyTests), a block list and the script it stops (BlockingTests), a plain-http page and one to come back to from a refused address (PlainHTTPTests),
links and a script redirect to other apps' addresses (ExternalLinkTests) and, given a certificate, the same pages over
HTTPS with that certificate, which the simulator can't verify (CertificateTests). No external
requests."""
import argparse
import html
import struct
import zlib
import ssl
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit


def square_png(size=300, rgb=(255, 99, 71)):
    """A solid size × size PNG, made here so the fixtures need no files (LinkMenuTests' Save to Photos, #713)."""
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    row = b'\x00' + bytes(rgb) * size
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(row * size)) + chunk(b'IEND', b''))


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

    def text(self, body, content_type='text/plain'):
        encoded = body.encode()
        self.send_response(200)
        self.send_header('Content-Type', f'{content_type}; charset=utf-8')
        self.send_header('Content-Length', str(len(encoded)))
        self.send_header('Cache-Control', 'no-store')
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
        elif url.path == '/picture':
            # A picture to long-press for WebKit's image menu (LinkMenuTests, Save to Photos, #713).
            self.page('<title>Picture</title><h1>Picture</h1>'
                      '<img alt="Square" src="/picture.png" style="width:240px;height:240px">')
        elif url.path == '/picture.png':
            data = square_png()
            self.send_response(200)
            self.send_header('Content-Type', 'image/png')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif url.path == '/plain':
            # A plain-http page (PlainHTTPTests), opened by a domain name: iOS's App Transport
            # Security lets IP addresses and plain `localhost` through, but not `cra.localhost`.
            self.page('<title>Plain HTTP Fixture</title><h1>Plain HTTP Fixture</h1>')
        elif url.path == '/themed':
            # A page with a theme-color, long enough to scroll under the status bar (StatusBandTests, #657).
            self.page('<meta name="theme-color" content="#7F6BAB"><title>Themed</title><h1>Themed</h1>'
                      '<p style="height:3000px">Long</p>')
        elif url.path == '/dark-page':
            # No theme-color, a dark background of its own (StatusBandTests, #657).
            self.page('<title>Dark Page</title><style>html,body{background:#123456;color:white}</style>'
                      '<h1>Dark Page</h1>')
        elif url.path == '/long-article':
            # A long page to scroll down and find again after the app is closed (PageRestoreTests, #656).
            self.page('<title>Long Article</title><h1>Long Article</h1>'
                      + ''.join('<p>Paragraph %d of a long article, with enough words to take a few lines on a phone.</p>' % n
                                for n in range(1, 121)))
        elif url.path == '/before-refused':
            # A page to come back to from the error page of an address WebKit refuses (port 1).
            self.page('<title>Before Refused</title><h1>Before Refused</h1>')
        elif url.path == '/schemes':
            # Links to addresses another app handles (ExternalLinkTests). The simulator has no Mail
            # or Phone app, so mailto: and tel: find no app; Messages takes sms:.
            self.page('<title>Scheme Links</title><h1>Scheme Links</h1>'
                      '<p><a href="mailto:fixture@cra.test">Write an email</a></p>'
                      '<p><a href="tel:+4512345678">Call the fixture</a></p>'
                      '<p><a href="sms:+4512345678">Text the fixture</a></p>')
        elif url.path == '/scheme-redirect':
            # A script sends the page to a mailto: address with no tap.
            self.page('<title>Scheme Redirect</title><h1>Scheme Redirect</h1>'
                      "<script>setTimeout(() => { location.href = 'mailto:fixture@cra.test'; }, 300);</script>")
        elif url.path == '/cra-570/list.txt':
            # A block list in Adblock Plus syntax (BlockingTests, #570): a path rule for a script on
            # a host no list has, a hiding rule, and a scriptlet Cra can't run.
            self.text('[Adblock Plus 2.0]\n! Title: Cra test list 570\n'
                      '/cra-570-ads/loader.js$script\n##.cra-570-banner\ncra.localhost##+js(nowoif)\n')
        elif url.path == '/cra-570/page':
            # A page asking for that script from cra.localhost (the loopback by another name); its
            # title says whether the script loaded or was stopped.
            script = f'http://cra.localhost:{self.server.server_port}/cra-570-ads/loader.js'
            self.page('<title>waiting</title><h1>Path rule</h1>'
                      f'<script src="{script}" onload="document.title=\'loader-ran\'" '
                      'onerror="document.title=\'loader-stopped\'"></script>')
        elif url.path == '/cra-570-ads/loader.js':
            # What that path rule stops; let through, it loads.
            self.text('window.craLoaderRan = true;\n', 'text/javascript')
        elif url.path == '/untrusted':
            self.page('<title>Untrusted Fixture</title><h1>Untrusted Fixture</h1>')
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
    parser.add_argument('--tls-cert', help='a self-signed certificate (PEM) to serve HTTPS with')
    parser.add_argument('--tls-key', help="that certificate's private key (PEM)")
    parser.add_argument('--tls-port', type=int, default=18766)
    options = parser.parse_args()
    if options.tls_cert:
        secure = ThreadingHTTPServer(('127.0.0.1', options.tls_port), PopupHandler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(options.tls_cert, options.tls_key)
        secure.socket = context.wrap_socket(secure.socket, server_side=True)
        threading.Thread(target=secure.serve_forever, daemon=True).start()
        print(f'Untrusted fixtures: https://127.0.0.1:{secure.server_port}/untrusted', flush=True)
    server = ThreadingHTTPServer(('127.0.0.1', options.port), PopupHandler)
    print(f'Popup fixtures: http://127.0.0.1:{server.server_port}/source', flush=True)
    server.serve_forever()
