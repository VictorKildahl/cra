#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests
clang++ -std=c++20 -Wall -Wextra -Werror Tests/PipeWriterTests.cpp -o .build/tests/pipe-writer-tests
.build/tests/pipe-writer-tests
