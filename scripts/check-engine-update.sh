#!/bin/bash
# Does the engine (scripts/fetch-engine.sh) have every security fix Chrome stable has shipped? Chromium fixes
# security bugs only in its newest builds, so a release ships an engine that has them all.
#   scripts/check-engine-update.sh           print the engine, Chrome stable and each recent security fix
#   scripts/check-engine-update.sh --check   exit 1 when the engine lacks one or is older than stable (release.sh,
#                                             scripts/check-cef-release-hook.sh)
#   scripts/check-engine-update.sh --issue   when it does, open (or update) one "Chromium engine update available"
#                                             issue naming the CVEs and the build to move to (hourly,
#                                             .github/workflows/engine-updates.yml)
# It compares fixes, not version numbers: on 159 Beta the old number check let 158's critical CVE-2026-134401
# through (scripts/engine-security.py says how, Tests/test_engine_security.py pins it).
# To update: CHROMIUM_TAG=<build> scripts/build-chromium.sh, for both CPUs, then scripts/publish-engine.sh and
# a new ENGINE_VERSION in fetch-engine.sh (docs/chromium-engine.md).
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 -I scripts/engine-security.py "$@"
