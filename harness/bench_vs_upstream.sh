#!/bin/bash
# Head-to-head: stock upstream (-O2) vs the optimized fork (PGO, held-out
# training by default). Writes results/upstream_o2.csv, results/fork_pgo.csv and
# results/summary.csv.
#
# usage: harness/bench_vs_upstream.sh
#   CC, BUDGET, REPEATS, PIN   knobs (see harness/bench.sh)
#   TRAIN_SET=all|heldout      PGO corpus (default heldout)
#   CAND_FLAGS                 candidate flags (default -O3 -march=x86-64-v3 -ffp-contract=off)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CC=${CC:-clang}
export CC
BUDGET=${BUDGET:-0.1}
REPEATS=${REPEATS:-7}
PIN=${PIN:-2}
TRAIN_SET=${TRAIN_SET:-heldout}
CAND_FLAGS=${CAND_FLAGS:-"-O3 -march=x86-64-v2 -ffp-contract=off"}
export BUDGET REPEATS PIN TRAIN_SET

echo "### baseline: upstream -O2"
BUDGET=$BUDGET REPEATS=$REPEATS bash "$ROOT/harness/bench.sh" upstream_o2 upstream -O2

echo "### candidate: fork + PGO (train=$TRAIN_SET)"
PGO_DIR="$ROOT/build/pgo_vs" bash "$ROOT/harness/bench.sh" fork_pgo src $CAND_FLAGS

python3 - "$ROOT" <<'PY'
import csv, math, sys, os
root = sys.argv[1]
def load(p):
    d = {}
    for r in csv.DictReader(open(p)):
        try: d[r["file"]] = float(r["ns_per_pixel"])
        except Exception: pass
    return d
up = load(os.path.join(root, "results/upstream_o2.csv"))
fk = load(os.path.join(root, "results/fork_pgo.csv"))
rows = []
ratios = []
for f in up:
    if f in fk and fk[f] > 0:
        r = up[f] / fk[f]
        rows.append((f, up[f], fk[f], r)); ratios.append(r)
rows.sort(key=lambda x: x[3])
gm = math.exp(sum(math.log(r) for r in ratios) / len(ratios)) if ratios else 0.0
print(f"\n{'file':52s} {'upstream':>9s} {'fork':>9s} {'speedup':>8s}")
for f, a, b, r in rows:
    print(f"{f:52s} {a:9.4f} {b:9.4f} {r:7.3f}x")
print(f"\ngeomean speedup over {len(ratios)} files: {gm:.4f}x  ({(gm-1)*100:+.1f}%)")
with open(os.path.join(root, "results/summary.csv"), "w") as out:
    out.write("file,upstream_ns_per_pixel,fork_ns_per_pixel,speedup\n")
    for f, a, b, r in rows:
        out.write(f"{f},{a},{b},{r}\n")
    out.write(f"GEOMEAN,,,{gm}\n")
PY
