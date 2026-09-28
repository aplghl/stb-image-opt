#!/bin/bash
# Regenerate the local corpus deterministically. Requires Pillow (python3).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR="$ROOT/corpus"
PY=${PY:-python3}

"$PY" "$DIR/gen_corpus.py"

CC=${CC:-gcc}
"$CC" -O2 -I "$ROOT/upstream" "$ROOT/tools/gen_hdr.c" -lm -o "$ROOT/build/gen_hdr"
"$ROOT/build/gen_hdr" "$DIR"

echo "corpus ready in $DIR"
