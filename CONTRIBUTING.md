# Contributing

Thanks for helping optimize `stb_image`. This is a performance fork, and the
guiding rule is simple:

> **Every accepted change must keep the exact build bit-identical to upstream.**

Speed is worthless if it changes a single decoded byte.

## Ground rules

- The public API, structs, ABI and default behavior must not change.
- `upstream/` is the pristine oracle. Never edit it.
- Only `src/stb_image.h` (and the surrounding harness/build files) may change.
- Put new SIMD behind the existing gating: compile-time `#ifdef STBI_AVX2` /
  `STBI_SSE2` / `STBI_NEON`, selected at runtime at the existing dispatch
  points. New kernels must have a scalar fallback.
- New AVX2 kernels carry `STBI_TARGET_AVX2` and `STBI__NOINLINE`, and must be
  reachable via `STBI_FORCE_AVX2`.

## Before opening a pull request

Run the full gate and make sure it is green:

```sh
source scripts/env.sh          # optional hermetic toolchain
make verify                    # bit-exact on all dispatch paths
make verify-portable           # SSE-only / no-SIMD / ONLY_* / C++ / cross-targets
make sanitize                  # ASan + UBSan
make fuzz ARGS=60              # libFuzzer
```

If you add a kernel, also run `make kernels` or extend `bench/kernbench.c` and
report the isolated speedup plus the end-to-end effect
(`make bench-vs-upstream`).

## Adding a kernel

1. Copy the scalar/SSE2 reference into a new `STBI_TARGET_AVX2` function with
   identical per-lane semantics.
2. Wire it into the relevant dispatcher (`stbi__setup_jpeg`, ...), preserving
   the scalar fallback.
3. Confirm `harness/dispatch.sh` passes for every forced path.
4. Benchmark; if it is not a clear win, say so and keep the scalar path —
   experiments that did not help are documented in `NOTES.md`.

## Reporting

Keep commit messages concise and factual. In the PR, include: what changed, the
measured speedup (with hardware/compiler), and the verification commands run.
