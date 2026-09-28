#!/bin/bash
# libFuzzer gate (clang). Seeds from the corpus; stops on the first crash.
#
# usage: harness/fuzz.sh [seconds]
#   SECONDS (default 60), JOBS (default 1)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
mkdir -p "$BUILD/fuzz_seed"
CC=${CC:-clang}
SECONDS=${1:-60}
JOBS=${JOBS:-1}

# Seed corpus: small samples across formats.
find "$ROOT/upstream/tests/pngsuite/primary" -name '*.png' 2>/dev/null | head -40 | while read -r f; do cp "$f" "$BUILD/fuzz_seed/"; done
for f in "$ROOT"/corpus/*.png "$ROOT"/corpus/*.gif "$ROOT"/corpus/*.bmp "$ROOT"/corpus/*.tga "$ROOT"/corpus/*.psd "$ROOT"/corpus/*.hdr "$ROOT"/corpus/*q50*.jpg; do
    [ -e "$f" ] && cp "$f" "$BUILD/fuzz_seed/" 2>/dev/null
done

echo "== libFuzzer (${SECONDS}s, jobs=$JOBS) =="
$CC -O1 -g -fsanitize=fuzzer,address,undefined -fno-sanitize-recover=all \
    -I "$ROOT/src" "$ROOT/tools/stbi_fuzz.c" -lm -o "$BUILD/stbi_fuzz" || exit 1

"$BUILD/stbi_fuzz" -max_total_time="$SECONDS" -jobs="$JOBS" -workers="$JOBS" \
    -rss_limit_mb=4096 "$BUILD/fuzz_seed" -artifact_prefix="$BUILD/fuzz_"
rc=$?
if [ $rc -eq 0 ]; then echo "PASS: fuzzer clean"; else echo "FAIL: fuzzer found a problem (rc=$rc)"; fi
exit $rc
