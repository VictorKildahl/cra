#!/usr/bin/env python3
"""scripts/check-cef-update.sh --check: when is Cra behind the newest stable CEF? No network.

GitHub #355: Spotify's index listed CEF 156.0.28 on Chromium .88 while Cra pinned 156.0.27 on
Chromium .96 (CEF's branch head built on a newer Chromium tag). The checker compared the whole
version string, called .88 newer, opened an update issue and blocked the release.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/check-cef-update.sh"
OURS = "156.0.27+ga10dae3+chromium-156.0.8078.96"


class CheckTests(unittest.TestCase):
    def check(self, pinned, latest):
        """Exit code of --check with `pinned` in fetch-cef.sh and `latest` as Spotify's stable."""
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "scripts").mkdir()
            shutil.copy(SCRIPT, root / "scripts")
            (root / "scripts/fetch-cef.sh").write_text(f'CEF_VERSION="{pinned}"\n')
            index = {"macosarm64": {"versions": [
                {"channel": "beta", "cef_version": "999.0.0+gbeta+chromium-999.0.0.0"},
                {"channel": "stable", "cef_version": latest},
                {"channel": "stable", "cef_version": "1.0.0+gold+chromium-1.0.0.0"},
            ]}}
            (root / "index.json").write_text(json.dumps(index))
            curl = root / "bin/curl"
            curl.parent.mkdir()
            curl.write_text(f'#!/bin/sh\ncat "{root}/index.json"\n')
            curl.chmod(0o755)
            env = dict(os.environ, PATH=f"{curl.parent}{os.pathsep}{os.environ['PATH']}")
            result = subprocess.run([str(root / "scripts/check-cef-update.sh"), "--check"],
                                    env=env, capture_output=True, text=True)
            self.assertIn(result.returncode, (0, 1), result.stderr)
            return result.returncode

    def test_same_version_is_current(self):
        self.assertEqual(self.check(OURS, OURS), 0)

    def test_newer_cef_on_older_chromium_is_current(self):
        # #355: moving to it would take Chromium back from .96 to .88.
        self.assertEqual(self.check(OURS, "156.0.28+g57389f0+chromium-156.0.8078.88"), 0,
                         "a newer CEF on an older Chromium patch must not count as an update")

    def test_older_cef_on_older_chromium_is_current(self):
        self.assertEqual(self.check(OURS, "156.0.26+g1111111+chromium-156.0.8078.88"), 0)

    def test_older_cef_on_same_chromium_is_current(self):
        self.assertEqual(self.check(OURS, "156.0.26+g1111111+chromium-156.0.8078.96"), 0)

    def test_newer_cef_on_same_chromium_is_behind(self):
        self.assertEqual(self.check(OURS, "156.0.28+g2222222+chromium-156.0.8078.96"), 1)

    def test_newer_chromium_patch_is_behind(self):
        self.assertEqual(self.check(OURS, "156.0.29+g3333333+chromium-156.0.8078.120"), 1)

    def test_newer_chromium_patch_on_older_cef_is_behind(self):
        self.assertEqual(self.check(OURS, "156.0.26+g4444444+chromium-156.0.8078.120"), 1)

    def test_new_chromium_major_is_behind(self):
        self.assertEqual(self.check(OURS, "157.0.1+g5555555+chromium-157.0.8100.10"), 1)

    def test_older_pin_is_behind(self):
        self.assertEqual(self.check("156.0.26+g1111111+chromium-156.0.8078.88", OURS), 1)


if __name__ == "__main__":
    unittest.main()
