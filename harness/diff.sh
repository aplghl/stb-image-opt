#!/bin/bash
# Bit-exact differential test: candidate (src/) vs pristine upstream oracle (upstream/).
#
# Builds decode_dump twice, decodes every corpus image under several APIs
# (stbi_load req_comp 0..4, stbi_load_16, stbi_loadf, GIF frames, stbi_info)
# and requires byte-identical stdout and identical exit codes.
#
# The oracle is ALWAYS built with canonical upstream flags (-O2) so any numeric
# change caused by candidate source changes OR candidate flags is caught.
#
# usage: harness/diff.sh [candidate flags...]
#   PGO_DIR=/abs/dir        two-pass profile-generate/use for the candidate
#   ORACLE_FLAGS="..."      override oracle flags (default "-O2")
#   CC=clang                compiler (defaults to clang if present, else gcc)
#   QUIET=1                 only print summary
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build"
mkdir -p "$BUILD"

if [ -z "${CC:-}" ]; then
    if command -v clang >/dev/null 2>&1; then CC=clang; else CC=gcc; fi
fi
export CC

CAND_FLAGS=${CAND_FLAGS:-"-O2"}
[ $# -gt 0 ] && CAND_FLAGS="$*"
ORACLE_FLAGS=${ORACLE_FLAGS:-"-O2"}
PGO_DIR=${PGO_DIR:-""}
QUIET=${QUIET:-0}

# Corpus: upstream test assets + local corpus/.
list_corpus() {
    find "$ROOT/upstream/tests/pngsuite" -type f -name '*.png' 2>/dev/null
    find "$ROOT/upstream/tests/pbm" -type f \( -name '*.pgm' -o -name '*.ppm' \) 2>/dev/null
    find "$ROOT/corpus" -type f \
        \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' \
        -o -iname '*.bmp' -o -iname '*.tga' -o -iname '*.psd' -o -iname '*.pic' \
        -o -iname '*.pnm' -o -iname '*.ppm' -o -iname '*.pgm' -o -iname '*.hdr' \) 2>/dev/null
}

# PGO training corpus: a representative subset of the images above.
list_train() {
    list_corpus
}

echo "== differential: oracle='$ORACLE_FLAGS' candidate='$CAND_FLAGS' pgo='${PGO_DIR:-none}' cc=$CC =="

$CC $ORACLE_FLAGS -I "$ROOT/upstream" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/dump_oracle" || exit 1

if [ -n "$PGO_DIR" ]; then
    rm -rf "$PGO_DIR" && mkdir -p "$PGO_DIR"
    $CC $CAND_FLAGS -fprofile-generate="$PGO_DIR" -I "$ROOT/src" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/dump_cand" || exit 1
    while IFS= read -r f; do
        [ -e "$f" ] || continue
        "$BUILD/dump_cand" "$f" 0 u8 >/dev/null 2>&1
    done < <(list_train)
    case "$CC" in
      *clang*)
        llvm-profdata merge -output="$PGO_DIR/default.profdata" "$PGO_DIR"/*.profraw || exit 1
        $CC $CAND_FLAGS -fprofile-use="$PGO_DIR/default.profdata" -I "$ROOT/src" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/dump_cand" || exit 1
        ;;
      *)
        $CC $CAND_FLAGS -fprofile-use="$PGO_DIR" -fprofile-correction -I "$ROOT/src" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/dump_cand" || exit 1
        ;;
    esac
else
    $CC $CAND_FLAGS -I "$ROOT/src" "$ROOT/tools/decode_dump.c" -lm -o "$BUILD/dump_cand" || exit 1
fi

O="$BUILD/dump_oracle"
C="$BUILD/dump_cand"
fail=0
n=0
nfail=0

# compare <description> <args...>
compare() {
    local desc=$1; shift
    "$O" "$@" > "$BUILD/_o.bin" 2>/dev/null; local ro=$?
    "$C" "$@" > "$BUILD/_c.bin" 2>/dev/null; local rc=$?
    n=$((n + 1))
    if [ "$ro" != "$rc" ] || ! cmp -s "$BUILD/_o.bin" "$BUILD/_c.bin"; then
        [ "$QUIET" = 1 ] || echo "DIFF [$desc] oracle_rc=$ro cand_rc=$rc: ${1#$ROOT/}"
        fail=1; nfail=$((nfail + 1))
    fi
}

while IFS= read -r f; do
    [ -e "$f" ] || continue
    for req in 0 1 2 3 4; do
        compare "u8 req=$req"  "$f" "$req" u8
        compare "u16 req=$req" "$f" "$req" u16
        compare "f32 req=$req" "$f" "$req" f32
    done
    compare "info" --info "$f"
    case "${f,,}" in
        *.gif) compare "gif" --gif "$f" ;;
    esac
done < <(list_corpus)

rm -f "$BUILD/_o.bin" "$BUILD/_c.bin"
if [ "$fail" -eq 0 ]; then
    echo "PASS: $n checks bit-exact"
else
    echo "FAIL: $nfail of $n checks diverged"
fi
exit $fail
