# stb-image-opt convenience targets. Source scripts/env.sh first so the hermetic
# clang/zig toolchain is on PATH (or override CC).
#
# The oracle is ALWAYS the pristine upstream header; only src/ is modified.

ROOT := $(CURDIR)
# Use the hermetic clang by default; override with `make CC=gcc`.
ifeq ($(origin CC),default)
CC := clang
endif
export CC

# Recommended exact build (bit-identical; see NOTES.md for the flag study).
EXACT_FLAGS ?= -O3 -march=x86-64-v2 -ffp-contract=off
FAST_FLAGS  ?= -O3 -march=x86-64-v2 -ffast-math
PORTABLE_FLAGS ?= -O2

.PHONY: all verify verify-portable dispatch sanitize fuzz bench bench-vs-upstream \
        kernels corpus clean help

all: verify

## Full correctness gate: all ISA paths bit-exact vs the pristine oracle.
verify:
	bash harness/diff.sh $(EXACT_FLAGS)
	bash harness/dispatch.sh $(EXACT_FLAGS)

## Retained for API parity with the other forks.
dispatch:
	bash harness/dispatch.sh $(EXACT_FLAGS)

## Portability matrix: SSEx-only, no-SIMD, format toggles, cross-targets.
verify-portable:
	bash harness/portable.sh

## ASan+UBSan over corpus + truncations + mutations.
sanitize:
	bash harness/sanitize.sh

## libFuzzer (seconds configurable: make fuzz ARGS=120).
fuzz:
	bash harness/fuzz.sh $(or $(ARGS),60)

## Throughput benchmark of the candidate (writes results/src_exact.csv).
bench:
	bash harness/bench.sh src_exact src $(EXACT_FLAGS)

## Head-to-head vs stock upstream -O2 (writes results/summary.csv).
bench-vs-upstream:
	bash harness/bench_vs_upstream.sh

## Per-kernel microbenchmarks (YCbCr scalar vs SSE2 vs AVX2).
kernels:
	bash harness/kernbench.sh

## Regenerate the deterministic image corpus (requires Pillow).
corpus:
	bash corpus/gen_corpus.sh

clean:
	rm -rf build gmon.out

help:
	@grep -E '^## ' Makefile | sed 's/^## //'
