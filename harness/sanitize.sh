#!/bin/bash
# Sanitizer gate: AddressSanitizer + UBSan (clang) over the whole corpus, plus
# truncated prefixes and deterministic pseudo-random mutated buffers, so the
# decode paths (and the runtime AVX2/SSE2/scalar dispatch) are exercised on
# malformed input.
#
# usage: harness/sanitize.sh [extra flags...]
#   FUZZ_N=<n>   pseudo-random buffers per seed (default 150)
#   TRUNC=<n>    truncation points per file (default 4)
#   SAN=...      sanitizer set (default "address,undefined")
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
mkdir -p "$BUILD"
CC=${CC:-clang}
FLAGS=${*:-"-O1 -g -march=x86-64-v3 -ffp-contract=off"}
SAN=${SAN:-"address,undefined"}
SANFLAGS="-fsanitize=$SAN -fno-sanitize-recover=all -fno-omit-frame-pointer"
FUZZ_N=${FUZZ_N:-150}
TRUNC=${TRUNC:-4}

echo "== sanitizers: $FLAGS $SANFLAGS =="
$CC $FLAGS $SANFLAGS -I "$ROOT/src" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/dump_asan" || exit 1

list_corpus() {
    find "$ROOT/upstream/tests/pngsuite" "$ROOT/upstream/tests/pbm" "$ROOT/corpus" -type f \
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' \
        -o -iname '*.bmp' -o -iname '*.tga' -o -iname '*.psd' -o -iname '*.pic' \
        -o -iname '*.pnm' -o -iname '*.ppm' -o -iname '*.pgm' -o -iname '*.hdr' \) 2>/dev/null
}

fail=0; n=0
run() {
    out=$("$BUILD/dump_asan" "$1" "${2:-0}" "${3:-u8}" 2>&1 >/dev/null); rc=$?
    n=$((n + 1))
    if [ $rc -gt 1 ] || echo "$out" | grep -qE "Sanitizer|runtime error"; then
        echo "SANITIZER: $1 req=${2:-0} ${3:-u8} (rc=$rc)"
        echo "$out" | head -12
        fail=1
    fi
}

for f in $(list_corpus); do
    [ -e "$f" ] || continue
    run "$f" 0 u8; run "$f" 4 u8; run "$f" 4 u16
    size=$(stat -c%s "$f")
    for t in $(seq 1 "$TRUNC"); do
        len=$(( size * t / (TRUNC + 1) ))
        [ "$len" -gt 0 ] || continue
        head -c "$len" "$f" > "$BUILD/_trunc.bin"
        run "$BUILD/_trunc.bin" 0 u8; run "$BUILD/_trunc.bin" 4 u8
    done
done

# deterministic mutations of a few seeds
seeds=(upstream/tests/pngsuite/primary/basn2c08.png corpus/plasma_512.png corpus/plasma_512_q85_p0_s2.jpg corpus/anim.gif)
for s in "${seeds[@]}"; do
    [ -e "$ROOT/$s" ] || continue
    for i in $(seq 1 "$FUZZ_N"); do
        python3 - "$ROOT/$s" "$BUILD/_rand.bin" "$i" <<'PY'
import random, sys
data = bytearray(open(sys.argv[1], "rb").read())
rng = random.Random(int(sys.argv[3]))
for _ in range(max(1, len(data)//100)):
    if data: data[rng.randrange(len(data))] ^= 1 << rng.randrange(8)
if rng.random() < 0.5 and len(data) > 16:
    data = data[:rng.randrange(1, len(data))]
open(sys.argv[2], "wb").write(data)
PY
        run "$BUILD/_rand.bin" 0 u8
    done
done

rm -f "$BUILD/_trunc.bin" "$BUILD/_rand.bin"
if [ "$fail" -eq 0 ]; then echo "PASS: sanitizers clean ($n inputs)"; else echo "FAIL: sanitizer error"; fi
exit $fail
