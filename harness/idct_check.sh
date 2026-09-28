#!/bin/bash
# Isolated bit-exactness check for the AVX2 two-block IDCT: compares
# stbi__idct_block_avx2 against stbi__idct_simd / stbi__idct_block on generated
# coefficient blocks (zeros, DC-only, sparse, full-range, extremes).
#
# usage: harness/idct_check.sh [iters]
#   CC=clang   compiler (defaults to clang if present, else gcc)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
mkdir -p "$BUILD"
ITERS=${1:-200000}

if [ -z "${CC:-}" ]; then
    if command -v clang >/dev/null 2>&1; then CC=clang; else CC=gcc; fi
fi

FLAGS=${IDCT_FLAGS:-"-O2 -march=x86-64-v2 -ffp-contract=off"}
$CC $FLAGS -I "$ROOT/src" "$ROOT/tools/idct_check.c" -lm -o "$BUILD/idct_check" || exit 1
"$BUILD/idct_check" "$ITERS"
