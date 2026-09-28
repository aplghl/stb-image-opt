#!/bin/bash
# Build the drop-in static library with the recommended flags, optionally with
# multi-workload PGO. The public API/ABI is the original stb_image one.
#
# usage: scripts/build_opt.sh [exact|fast] [outdir]
#   exact (default): bit-identical to upstream; -ffp-contract=off
#   fast           : allows FMA/reassociation (-ffast-math), not bit-exact
#
# env: CC (default clang), PGO=1 to train on the corpus, ARCH (default x86-64-v2)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-exact}
OUT=${2:-"$ROOT/build/lib_$MODE"}
CC=${CC:-clang}
ARCH=${ARCH:-x86-64-v2}
PGO=${PGO:-0}

case "$MODE" in
    exact) FPF="-ffp-contract=off" ;;
    fast)  FPF="-ffast-math" ;;
    *) echo "unknown mode: $MODE (expected exact|fast)"; exit 2 ;;
esac
FLAGS="-O3 -march=$ARCH $FPF"
mkdir -p "$OUT"

if [ "$PGO" = "1" ]; then
    PROF="$ROOT/build/pgo_lib_$MODE"
    rm -rf "$PROF" && mkdir -p "$PROF"
    # Pass 1: instrument the (header-only) image code via the training driver.
    $CC $FLAGS -fprofile-generate="$PROF" -I "$ROOT/src" "$ROOT/tools/decode_dump.c" -lm -o "$OUT/train"
    find "$ROOT/corpus" "$ROOT/upstream/tests/pngsuite" -type f \
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.gif' -o -iname '*.bmp' \
        -o -iname '*.tga' -o -iname '*.psd' -o -iname '*.hdr' \) 2>/dev/null |
    while IFS= read -r f; do "$OUT/train" "$f" 4 u8 >/dev/null 2>&1 || true; done
    # Pass 2: rebuild the library object with the merged profile.
    case "$CC" in
      *clang*) llvm-profdata merge -output="$PROF/default.profdata" "$PROF"/*.profraw
               $CC $FLAGS -fprofile-use="$PROF/default.profdata" -I "$ROOT/src" -c "$ROOT/lib/stb_image.c" -o "$OUT/stb_image.o" ;;
      *)       $CC $FLAGS -fprofile-use="$PROF" -fprofile-correction -I "$ROOT/src" -c "$ROOT/lib/stb_image.c" -o "$OUT/stb_image.o" ;;
    esac
    rm -f "$OUT/train"
else
    $CC $FLAGS -I "$ROOT/src" -c "$ROOT/lib/stb_image.c" -o "$OUT/stb_image.o"
fi

ar rcs "$OUT/libstb_image_opt.a" "$OUT/stb_image.o"
cp "$ROOT/src/stb_image.h" "$OUT/stb_image.h"
echo "built $OUT/libstb_image_opt.a (mode=$MODE arch=$ARCH pgo=$PGO)"
