#!/usr/bin/env python3
"""CEF download failures and fallback integrity, without network or Chromium."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/download-cef.py"
URL = "https://github.com/VictorKildahl/cra/releases/download/cef-test/cef_binary_macosarm64_minimal.tar.bz2"
PAYLOAD = b"CEF archive fixture"

class DownloadTests(unittest.TestCase):
    def run_download(self, mode, url=URL):
        folder = Path(self.temp.name)
        env = dict(os.environ, PATH=str(folder) + os.pathsep + os.environ['PATH'],
                   DOWNLOAD_MODE=mode, DOWNLOAD_LOG=str(folder / 'calls'))
        result = subprocess.run(['python3', str(SCRIPT), url, str(folder / 'archive')],
                                env=env, capture_output=True, text=True)
        calls = (folder / 'calls').read_text().splitlines()
        return result, calls, (folder / 'archive').read_bytes()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        folder = Path(self.temp.name)
        (folder / 'archive').write_bytes(b'existing archive')
        curl = folder / 'curl'
        curl.write_text('''#!/usr/bin/env python3
import hashlib,json,os,sys
from pathlib import Path
args=sys.argv[1:]; url=args[-1]; mode=os.environ['DOWNLOAD_MODE']
with open(os.environ['DOWNLOAD_LOG'],'a') as log: log.write(url+'\\n')
if 'api.github.com' not in url:
    if mode != 'direct': sys.exit(22)
    data=b'CEF archive fixture'
elif '/releases/tags/' in url:
    if mode == 'metadata-error': sys.exit(22)
    asset={'id':123,'name':'cef_binary_macosarm64_minimal.tar.bz2',
           'digest':'sha256:'+hashlib.sha256(b'CEF archive fixture').hexdigest()}
    if mode == 'missing-digest': asset.pop('digest')
    data=json.dumps({'assets':[] if mode == 'missing-asset' else [asset]}).encode()
else:
    data=b'corrupt archive' if mode == 'corrupt' else b'CEF archive fixture'
Path(args[args.index('--output')+1]).write_bytes(data)
''')
        curl.chmod(0o755)

    def test_direct_download_does_not_call_api(self):
        result,calls,data=self.run_download('direct')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(calls,[URL]); self.assertEqual(data,PAYLOAD)

    def test_release_failure_uses_verified_api_asset(self):
        result,calls,data=self.run_download('fallback')
        self.assertEqual(result.returncode,0,'A failed release download must recover through the official API: '+result.stderr)
        self.assertEqual(data,PAYLOAD)
        self.assertEqual(calls[-1],'https://api.github.com/repos/VictorKildahl/cra/releases/assets/123')

    def test_corrupt_fallback_preserves_existing_archive(self):
        result,_,data=self.run_download('corrupt')
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(data,b'existing archive')

    def test_metadata_failures_preserve_existing_archive(self):
        for mode in ['metadata-error','missing-asset','missing-digest']:
            with self.subTest(mode=mode):
                result,_,data=self.run_download(mode)
                self.assertNotEqual(result.returncode,0)
                self.assertEqual(data,b'existing archive')

    def test_custom_url_never_falls_back_to_cra_release(self):
        url='https://example.com/custom-cef.tar.bz2'
        result,calls,data=self.run_download('fallback',url)
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(calls,[url]); self.assertEqual(data,b'existing archive')

if __name__ == '__main__': unittest.main()
