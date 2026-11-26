#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
exec node --test Tests/FilterWorkerTests.js Tests/AdShieldRecoveryTests.js
