#!/bin/bash
# Per-kernel microbenchmarks -> results/kernels.csv.
# usage: harness/kernbench.sh [n] [iters]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"; RES="$ROOT/results"
mkdir -p "$BUILD" "$RES"
CC=${CC:-clang}
N=${1:-4096}
ITERS=${2:-50000}
PIN=${PIN:-2}
FLAGS=${KERN_FLAGS:-"-O3 -march=x86-64-v3 -ffp-contract=off"}

$CC $FLAGS -I "$ROOT/src" "$ROOT/bench/kernbench.c" -lm -o "$BUILD/kernbench" || exit 1

CSV="$RES/kernels.csv"
echo "kernel,n,iters,ns_per_pixel" > "$CSV"
for k in ycbcr_scalar ycbcr_sse2 ycbcr_avx2 idct_scalar idct_sse2 idct_avx2; do
    line=$(taskset -c "$PIN" "$BUILD/kernbench" "$k" "$N" "$ITERS")
    echo "$line" >> "$CSV"
    echo "$line"
done
python3 - "$CSV" <<'PY'
import csv, sys
d = {r["kernel"]: float(r["ns_per_pixel"]) for r in csv.DictReader(open(sys.argv[1]))}
if d.get("ycbcr_sse2") and d.get("ycbcr_avx2"):
    print(f"ycbcr: avx2 vs sse2 = {d['ycbcr_sse2']/d['ycbcr_avx2']:.3f}x, "
          f"vs scalar = {d['ycbcr_scalar']/d['ycbcr_avx2']:.3f}x")
if d.get("idct_sse2") and d.get("idct_avx2"):
    print(f"idct:  avx2 vs sse2 = {d['idct_sse2']/d['idct_avx2']:.3f}x, "
          f"vs scalar = {d['idct_scalar']/d['idct_avx2']:.3f}x")
PY
