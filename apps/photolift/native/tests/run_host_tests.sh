#!/usr/bin/env bash
# Host-side unit tests for photolift_tiling.h (no ncnn, no device needed).
# Compiles and runs native/tests/tiling_test.cpp with the system C++ compiler.
# Usage: native/tests/run_host_tests.sh
set -euo pipefail
cd "$(dirname "$0")"

CXX="${CXX:-g++}"
if ! command -v "$CXX" >/dev/null 2>&1; then
    if command -v clang++ >/dev/null 2>&1; then CXX=clang++; else
        echo "no C++ compiler found (set \$CXX)"; exit 2
    fi
fi

OUT="$(mktemp -d)/tiling_test"
"$CXX" -std=c++11 -O2 -Wall -Wextra tiling_test.cpp -o "$OUT"
"$OUT"
