#!/usr/bin/env python3
"""Recover an unavailable Cra release download through its verified GitHub API asset."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import quote

API = "https://api.github.com/repos/VictorKildahl/cra"


def download(url, destination, accept=None):
    command = ["curl", "--fail", "--location", "--retry", "2", "--connect-timeout", "15",
               "--max-time", "600", "--silent", "--show-error", "--output", str(destination)]
    if accept:
        command += ["--header", "Accept: " + accept]
    subprocess.run(command + [url], check=True)


def fetch(url, destination):
    # Keep any existing archive intact until either download path has succeeded.
    with tempfile.TemporaryDirectory(prefix="cef-download-", dir=destination.parent) as folder:
        archive = Path(folder) / "archive"
        try:
            download(url, archive)
        except subprocess.CalledProcessError:
            # A custom CEF_URL must never silently become a different Cra build.
            release = re.fullmatch(r"https://github\.com/VictorKildahl/cra/releases/download/([^/?#]+)/([^/?#]+)", url)
            if release is None:
                raise
            tag, name = release.groups()
            print("Release download failed; trying the same asset through GitHub's API.", file=sys.stderr)
            metadata = Path(folder) / "release.json"
            download(API + "/releases/tags/" + quote(tag, safe=""), metadata, "application/vnd.github+json")
            assets = json.loads(metadata.read_text())["assets"]
            asset = next((item for item in assets if item.get("name") == name), None)
            if asset is None:
                raise ValueError("The requested CEF asset is absent from the release.")
            digest = asset.get("digest", "")
            if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
                raise ValueError("The CEF asset has no verifiable SHA-256 digest.")
            identifier = asset.get("id")
            if type(identifier) is not int or identifier <= 0:
                raise ValueError("The CEF asset ID is invalid.")
            download(API + "/releases/assets/" + str(identifier), archive, "application/octet-stream")
            checksum = hashlib.sha256()
            with archive.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    checksum.update(chunk)
            if "sha256:" + checksum.hexdigest() != digest:
                raise ValueError("The CEF API download failed SHA-256 verification.")
        archive.replace(destination)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: download-cef.py URL DESTINATION")
    try:
        fetch(sys.argv[1], Path(sys.argv[2]))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit("CEF download failed: " + str(error))
