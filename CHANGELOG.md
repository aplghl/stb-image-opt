# Changelog

All notable changes to this fork are recorded here. This project tracks
[stb_image](https://github.com/nothings/stb) by version; the format follows
[Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added

- Runtime-dispatched **AVX2 two-block IDCT** (`stbi__idct_block_avx2`): two 8×8
  blocks in parallel, one per 128-bit lane, a direct widening of
  `stbi__idct_simd` and therefore byte-for-byte identical. The baseline
  non-interleaved, baseline interleaved (4:2:0/4:2:2 luma) and progressive
  `finish` IDCT loops pair adjacent blocks and fall back to SSE2 for leftovers.
  **1.81×** the SSE2 kernel in isolation; **≈ +4–8%** on JPEG decoding
  (`req_comp` 0–4) on top of the existing gains.
- Isolated IDCT bit-exactness check (`tools/idct_check.c`,
  `harness/idct_check.sh`, `make idct-check`), folded into `make verify`.

## [1.0.0] - 2026-09-28

Tracks `stb_image.h` v2.30 (upstream `nothings/stb` @ `2c980bb`).

### Added

- Runtime-dispatched **AVX2** fast path for `stbi__YCbCr_to_RGB_simd`
  (`stbi__YCbCr_to_RGB_avx2`): 16-pixel-wide, bit-identical to the SSE2 path,
  1.63× the SSE2 kernel in isolation. Accelerates `req_comp == 4` JPEG output.
- Portable runtime detection (`stbi__avx2_available`) via CPUID + `XGETBV`,
  with no libgcc `__cpu_model` dependency (links under `zig cc`).
- Path pinning for differential testing: `STBI_FORCE_AVX2`,
  `STBI_FORCE_SSE2`, `STBI_FORCE_SCALAR`.
- Differential harness (`harness/diff.sh`), dispatch matrix
  (`harness/dispatch.sh`), portability matrix (`harness/portable.sh`),
  sanitizer gate (`harness/sanitize.sh`), libFuzzer gate (`harness/fuzz.sh`),
  benchmarks (`harness/bench*.sh`, `harness/kernbench.sh`).
- Deterministic image corpus generator (`corpus/gen_corpus.sh`, Pillow).
- Hermetic, user-space toolchain bootstrap (`scripts/bootstrap_toolchain.sh`,
  checksum-pinned) and PGO artifact builder (`scripts/build_opt.sh`).
- `build.zig` producing a drop-in static library and cross-targets;
  `Makefile` convenience targets.

### Changed

- No changes to the public API, structs, ABI, or default decoded output. The
  default build remains bit-exact with upstream.

### Rejected (kept behind `STBI_AVX2_PNG_FILTER`, off by default)

- AVX2 PNG row unfiltering (Sub/Up/Avg/Paeth). Bit-exact but measurably slower
  than the scalar loops, which the compiler already auto-vectorizes. See
  `NOTES.md`.

[1.0.0]: https://github.com/aplghl/stb-image-opt/releases/tag/v1.0.0
