#!/bin/bash
# Portability gate: build the candidate under many supported configurations and
# cross-targets, and run a quick bit-exact check against the oracle for the
# native ones. Cross-targets are compile-only (no matching runtime here).
#
# usage: harness/portable.sh
#   CC (default clang), ZIG (default "zig cc")
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/portable"
mkdir -p "$BUILD"
CC=${CC:-clang}
ZIG_CC=${ZIG_CC:-"zig cc"}

# Native configs: <name>|<flags>
CONFIGS=(
  "default|-O2"
  "sse_only|-O2 -march=x86-64-v2"
  "no_simd|-O2 -DSTBI_NO_SIMD"
  "force_scalar|-O2 -DSTBI_FORCE_SCALAR"
  "force_sse2|-O2 -DSTBI_FORCE_SSE2"
  "force_avx2|-O2 -DSTBI_FORCE_AVX2"
  "only_png|-O2 -DSTBI_ONLY_PNG"
  "only_jpeg|-O2 -DSTBI_ONLY_JPEG"
  "no_stdio|-O2 -DSTBI_NO_STDIO"
)

SUBSET=(corpus/plasma_512_q85_p0_s2.jpg corpus/plasma_512.png corpus/anim.gif corpus/hdr_range.hdr)

fail=0
for c in "${CONFIGS[@]}"; do
    name=${c%%|*}; flags=${c#*|}
    printf '%-14s ' "$name"
    # Matching oracle built from the pristine header with the SAME toggles, so
    # format-disabling configs (ONLY_*/NO_*) are compared fairly.
    if ! $CC $flags -I "$ROOT/upstream" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/oracle" 2>"$BUILD/err"; then
        echo "ORACLE BUILD FAIL"; head -5 "$BUILD/err"; fail=1; continue
    fi
    if ! $CC $flags -I "$ROOT/src" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/cand" 2>"$BUILD/err"; then
        echo "BUILD FAIL"; head -5 "$BUILD/err"; fail=1; continue
    fi
    ok=1
    for rel in "${SUBSET[@]}"; do
        for req in 0 4; do
            "$BUILD/oracle" "$ROOT/$rel" "$req" u8 > "$BUILD/o.bin" 2>/dev/null
            "$BUILD/cand"   "$ROOT/$rel" "$req" u8 > "$BUILD/c.bin" 2>/dev/null
            cmp -s "$BUILD/o.bin" "$BUILD/c.bin" || { ok=0; echo "DIFF $rel req=$req"; }
        done
    done
    [ "$ok" = 1 ] && echo "OK" || fail=1
done

# C++ compile
printf '%-14s ' "cxx"
if $CC -x c++ -O2 -I "$ROOT/src" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/cxx" 2>"$BUILD/err"; then echo OK; else echo "BUILD FAIL"; head -5 "$BUILD/err"; fail=1; fi

# Cross-targets (compile-only) via zig cc; skipped if zig is not installed.
if command -v zig >/dev/null 2>&1; then
    for target in aarch64-linux-musl x86_64-windows-gnu aarch64-macos; do
        printf '%-14s ' "zig:$target"
        if $ZIG_CC -O3 -target "$target" -I "$ROOT/src" -c "$ROOT/tools/decode_dump.c" -o "$BUILD/dd_$target.o" 2>"$BUILD/err"; then
            echo OK
        else
            echo "BUILD FAIL"; head -5 "$BUILD/err"; fail=1
        fi
    done
else
    echo "zig            SKIP (zig not on PATH; run scripts/bootstrap_toolchain.sh zig)"
fi

rm -f "$BUILD"/o.bin "$BUILD"/c.bin
if [ "$fail" -eq 0 ]; then echo "PASS verify-portable"; else echo "FAIL verify-portable"; fi
exit $fail
