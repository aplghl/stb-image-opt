#!/bin/bash
# Verify every runtime-dispatched ISA path decodes bit-identically to the
# pristine upstream oracle: auto, forced SSE2, forced AVX2, forced scalar.
#
# usage: harness/dispatch.sh [candidate flags...]
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FLAGS=${*:-"-O2"}
fail=0
for isa in "" "-DSTBI_FORCE_SSE2" "-DSTBI_FORCE_AVX2" "-DSTBI_FORCE_SCALAR"; do
    name=${isa:-auto}
    echo "### ISA=${name#-DSTBI_FORCE_} ${isa:+($isa)}"
    QUIET=1 bash "$ROOT/harness/diff.sh" $FLAGS $isa || { fail=1; echo "  ^ FAILED ($name)"; }
done
if [ "$fail" -eq 0 ]; then echo "PASS: all ISA paths bit-exact"; else echo "FAIL: dispatch verification"; fi
exit $fail
