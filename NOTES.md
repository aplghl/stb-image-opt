# stb-image-opt — optimization notes

Target: Intel i7-14700F (Raptor Lake: AVX2 + FMA + BMI2, no AVX-512), WSL2.
Toolchain: hermetic, user-space **clang 23.1.2 + LLD**, **zig 0.16.0**,
**ispc 1.31.0**, `llvm-mca`/`llvm-bolt`, valgrind/callgrind, libFuzzer
(`scripts/bootstrap_toolchain.sh`, no sudo). Oracle: pristine `stb_image.h`
v2.30 (`nothings/stb` @ `2c980bb`).

Method was compiler-first, as in the parent strategy: build the bit-exact
differential + sanitizer harness first, claim compiler/PGO headroom, profile
with callgrind, then spend effort only on proven hot paths. Every accepted
source change is guarded and bit-exact.

## Correctness gates

- **Differential** (`harness/diff.sh`): oracle (`-O2`) vs candidate over the
  whole corpus — `upstream/tests/pngsuite` (258 PNGs incl. 16-bit/interlaced),
  `tests/pbm`, and the generated corpus (JPEG baseline+progressive, all
  subsampling ratios, grayscale; PNG RGB/RGBA/L/P; GIF static+animated; BMP,
  TGA, PSD, PNM, HDR) — for `stbi_load` `req_comp` 0–4, `stbi_load_16`,
  `stbi_loadf`, GIF frames and `stbi_info`. **12,306 checks**, byte-identical.
- **Dispatch** (`harness/dispatch.sh`): the same suite forced through
  auto / SSE2 / AVX2 / scalar. All bit-exact.
- **Cross-compiler**: clang, gcc 13.3, `zig cc` — all bit-exact.
- **Sanitizers** (`harness/sanitize.sh`): ASan+UBSan clean over 9,059 inputs
  (corpus + truncated prefixes + deterministic mutations).
- **Fuzzing** (`harness/fuzz.sh`): libFuzzer, clean.
- **Portability** (`harness/portable.sh`): SSEx-only, `STBI_NO_SIMD`,
  `STBI_ONLY_PNG`/`ONLY_JPEG`, `STBI_NO_STDIO`, C++ compile; aarch64-linux-musl,
  x86_64-windows-gnu, aarch64-macos cross-builds — all OK.

## What changed in `src/stb_image.h`

+243/−1 lines, additive and guarded; public API/ABI unchanged.

1. **AVX2 runtime dispatch infrastructure.** `STBI_AVX2`,
   `STBI_TARGET_AVX2` (`__attribute__((target("avx2")))`), and
   `stbi__avx2_available()` implemented with CPUID + `XGETBV` (deliberately not
   `__builtin_cpu_supports`, whose `__cpu_model` is unresolvable under
   `zig cc`). Path pinning via `STBI_FORCE_{AVX2,SSE2,SCALAR}`.
2. **`stbi__YCbCr_to_RGB_avx2`** — 16-pixel AVX2 YCbCr→RGB for 4-channel
   output. Same fixed-point constants and per-lane order as the SSE2 path; the
   pack/interleave is the SSE2 recipe widened to 256-bit plus two
   `_mm256_permute2x128_si256` to fix pixel order. Bit-identical, **1.63×** the
   SSE2 kernel in isolation (`results/kernels.csv`).

The header stays a single self-contained file; no new runtime dependency.

## Results

Held-out PGO (train on every corpus image except the measured 14), candidate
flags `-O3 -march=x86-64-v2 -ffp-contract=off`.

Mixed suite (14 files, `results/summary.csv`): **+6.3% geomean** vs upstream
`-O2`. Highlights: GIF **+20%**, progressive JPEG **+14%**, 8-bit palette PNG
+7–11%, 16-bit RGBA PNG +12%, HDR −1.5%.

JPEG → RGBA (`req_comp=4`, where the AVX2 YCbCr kernel is active), 4 JPEGs:
1.119×, 1.107×, 1.147×, 1.138× → **≈ +12.7% geomean**.

Kernel isolation (`make kernels`): YCbCr AVX2 = 0.127 ns/px vs SSE2 0.208
(**1.63×**) vs scalar 0.270 (**2.13×**).

Variance: repeated runs of the same build vary by a few percent per file; treat
individual ratios under ~3% as noise. The in-sample PGO gain was ~+7% vs the
held-out +6.3%, so PGO generalization is real but modest.

## Findings from the flag study

- Upstream's SSE2 kernels plus clang `-O2` are already strong. Compiler flags
  alone move little.
- `-march=x86-64-v3` **hurts** JPEG (e.g. 2.53 vs 2.37 ns/px) — the AVX
  auto-vectorizer does not help the entropy/IDCT code and the wider encoding
  costs. `-march=x86-64-v2` avoids this while still enabling the fork's AVX2
  kernels through runtime dispatch.
- `-O3` is neutral-to-positive, and clearly helps the GIF decoder (+~9%).
- LTO on a single translation unit is a wash; PGO is the real compiler lever.

## Rejected experiments (measured)

- **AVX2 PNG row unfiltering** (Sub/Up/Avg/Paeth, pixel-at-a-time 16-bit lanes,
  bit-exact). Measured **slower** for most PNGs (0.44×–0.99×): the scalar
  filter loops are already auto-vectorized by the compiler, and the loop-carried
  dependency at distance `bpp` forces a per-pixel path whose load/store overhead
  dominates. Kept behind the off-by-default `STBI_AVX2_PNG_FILTER` macro for
  reproducibility; see the comment in `src/stb_image.h`. The Paeth evaluation
  here is an independent implementation of the standard predictor (the same
  algorithm libpng uses); stb's own `stbi__paeth` was verified equivalent to the
  canonical definition over all 2^24 `(a,b,c)` inputs before porting.
- **gprof profiling** (`gcc -O2 -pg`) was misleading — it attributed 39% to
  YCbCr, while callgrind instruction counts and the kernel microbench show it
  is ~7%. Use callgrind (`valgrind`) or `llvm-mca`, not gprof, for this code.
- **`-march=x86-64-v3`** as the default (see above).
- **Full 256-bit interleave without permutes**: not possible; the two
  `permute2x128` are required and cheap.

## Remaining headroom (not taken)

- **PNG inflate** (`stbi__zhuffman_decode`, ~32% of PNG instructions) and
  **PNG filtering** (~46%) dominate PNG; both are serial/dependency-bound and
  resisted the SIMD approaches tried. A table-driven multi-bit Huffman decode
  is the most promising next step.
- **JPEG IDCT** (`stbi__idct_simd`, ~25% of JPEG instructions) and
  **`stbi__jpeg_decode_block`** (~26%): the existing SSE2 IDCT is already
  well-tuned; an AVX2 version needs a full SoA rewrite of the 8×8 transform.
- **`stbi__resample_row_hv_2_simd`** (~15% of JPEG): AVX2 needs cross-128-bit-lane
  shifts for the horizontal phase, doable but fiddly.
- **BOLT** (`llvm-bolt`) was not applied; it needs a profile and gives single
  digits on top of PGO. `perf`-based AutoFDO is impractical under WSL2 (no PMU).

## Reproduce

```sh
scripts/bootstrap_toolchain.sh all && source scripts/env.sh
make verify && make verify-portable && make sanitize && make fuzz ARGS=60
make bench-vs-upstream && REQ=4 bash harness/bench.sh up4 upstream -O2
make kernels
```

`results/README.md` maps every CSV to its generator.
