#!/bin/bash
# Build bench/bench.c against a header dir and measure the representative image
# suite. Writes results/<name>.csv and prints mean ns/pixel.
#
# usage: harness/bench.sh <name> <header_dir> [flags...]
#   PGO_DIR=/abs/dir   two-pass PGO for this build
#   BUDGET, REPEATS, PIN, CC
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=${1:?name required}
HDR=${2:?header dir required}
shift 2
FLAGS=${*:-"-O2"}
CC=${CC:-clang}
BUDGET=${BUDGET:-0.1}
REPEATS=${REPEATS:-5}
PIN=${PIN:-2}
REQ=${REQ:-0}
PGO_DIR=${PGO_DIR:-""}

BUILD="$ROOT/build"
RES="$ROOT/results"
mkdir -p "$BUILD" "$RES"
BIN="$BUILD/bench_$NAME"

HDR="$ROOT/$HDR"
[ -d "$HDR" ] || HDR="$2"

VECTORS=(
    corpus/grad_640_480_q85_p0_s2.jpg
    corpus/plasma_512_q85_p0_s2.jpg
    corpus/plasma_512_q85_p1_s0.jpg
    corpus/plasma_512_q10_p0_s2.jpg
    corpus/plasma_512.png
    corpus/plasma_512_pal.png
    corpus/plasma_512.psd
    corpus/anim.gif
    corpus/hdr_range.hdr
    upstream/tests/pngsuite/16bit/basn0g16.png
    upstream/tests/pngsuite/16bit/basn6a16.png
    upstream/tests/pngsuite/16bit/basi6a16.png
    upstream/tests/pngsuite/primary/basn2c16.png
    upstream/tests/pngsuite/primary/basn3p08.png
    upstream/tests/pngsuite/primary/basn0g01.png
)

# Training corpus for PGO. TRAIN_SET=heldout excludes the measured suite.
train_list() {
    if [ "${TRAIN_SET:-all}" = "heldout" ]; then
        find "$ROOT/corpus" "$ROOT/upstream/tests/pngsuite" "$ROOT/upstream/tests/pbm" -type f \
            \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' \
            -o -iname '*.bmp' -o -iname '*.tga' -o -iname '*.psd' -o -iname '*.pnm' \
            -o -iname '*.ppm' -o -iname '*.pgm' -o -iname '*.hdr' \) 2>/dev/null |
        while IFS= read -r f; do
            b=$(basename "$f"); keep=1
            for v in "${VECTORS[@]}"; do [ "$b" = "$(basename "$v")" ] && { keep=0; break; }; done
            [ "$keep" = 1 ] && echo "$f"
        done
    else
        for rel in "${VECTORS[@]}"; do echo "$ROOT/$rel"; done
    fi
}

echo "== bench $NAME: hdr=$HDR flags='$FLAGS' pgo='${PGO_DIR:-none}' train=${TRAIN_SET:-all} =="
if [ -n "$PGO_DIR" ]; then
    rm -rf "$PGO_DIR" && mkdir -p "$PGO_DIR"
    $CC $FLAGS -fprofile-generate="$PGO_DIR" -I "$HDR" "$ROOT/bench/bench.c" -lm -o "$BIN" || exit 1
    while IFS= read -r f; do
        [ -e "$f" ] || continue
        taskset -c "$PIN" "$BIN" "$f" 0.01 1 >/dev/null 2>&1
    done < <(train_list)
    case "$CC" in
      *clang*)
        llvm-profdata merge -output="$PGO_DIR/default.profdata" "$PGO_DIR"/*.profraw || exit 1
        $CC $FLAGS -fprofile-use="$PGO_DIR/default.profdata" -I "$HDR" "$ROOT/bench/bench.c" -lm -o "$BIN" || exit 1
        ;;
      *)
        $CC $FLAGS -fprofile-use="$PGO_DIR" -fprofile-correction -I "$HDR" "$ROOT/bench/bench.c" -lm -o "$BIN" || exit 1
        ;;
    esac
else
    $CC $FLAGS -I "$HDR" "$ROOT/bench/bench.c" -lm -o "$BIN" || exit 1
fi

CSV="$RES/$NAME.csv"
echo "file,bytes,w,h,comp,req,iters,ns_per_decode,ns_per_pixel,cycles_per_pixel,Mpixel_per_s" > "$CSV"
for rel in "${VECTORS[@]}"; do
    [ -e "$ROOT/$rel" ] || continue
    line=$(taskset -c "$PIN" "$BIN" "$ROOT/$rel" "$BUDGET" "$REPEATS" "$REQ")
    echo "${line//$ROOT\//}" >> "$CSV"
done

python3 - "$NAME" "$CSV" <<'PY'
import csv, sys
name, path = sys.argv[1], sys.argv[2]
vals = []
with open(path) as f:
    for row in csv.DictReader(f):
        try: vals.append(float(row["ns_per_pixel"]))
        except (KeyError, ValueError): pass
if vals:
    gm = 1.0
    for v in vals: gm *= v
    gm **= 1.0 / len(vals)
    print(f"{name}: n={len(vals)} mean_ns_per_pixel={sum(vals)/len(vals):.4f} geomean={gm:.4f}")
PY
