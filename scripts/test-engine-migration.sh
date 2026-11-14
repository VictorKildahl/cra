#!/bin/bash
# A Cra on CEF's data folder opens on the engine (docs/chromium-engine.md, step 4): a site's cookie and a tab's
# back and forward list carry over. Both apps are release builds of this checkout's app:
#   CEF_APP=<Cra on CEF>.app ENGINE_APP=<Cra on the engine>.app scripts/test-engine-migration.sh
set -uo pipefail
cd "$(dirname "$0")/.."
: "${CEF_APP:?CEF_APP=<a Cra.app on CEF>}" "${ENGINE_APP:=$PWD/build/Cra.app}"
DATA="$(mktemp -d /tmp/cra-migration.XXXXXX)"
trap 'rm -rf "$DATA"' EXIT
CRA_APP="$CEF_APP" CRA_SCENARIO_DATA="$DATA" scripts/scenario.sh Migration/cef-write || exit 1
CRA_APP="$ENGINE_APP" CRA_SCENARIO_DATA="$DATA" scripts/scenario.sh Migration/engine-read || exit 1
echo "Engine migration: passed"
