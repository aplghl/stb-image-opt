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
- **IDCT kernel** (`harness/idct_check.sh`): `stbi__idct_block_avx2` vs two
  `stbi__idct_simd` calls over 200k generated block pairs (all-zero, DC-only,
  sparse, full-range, extremes) in both output layouts. Bit-exact.
- **Cross-compiler**: clang, gcc 13.3, `zig cc` — all bit-exact.
- **Sanitizers** (`harness/sanitize.sh`): ASan+UBSan clean over 9,059 inputs
  (corpus + truncated prefixes + deterministic mutations).
- **Fuzzing** (`harness/fuzz.sh`): libFuzzer, clean.
- **Portability** (`harness/portable.sh`): SSEx-only, `STBI_NO_SIMD`,
  `STBI_ONLY_PNG`/`ONLY_JPEG`, `STBI_NO_STDIO`, C++ compile; aarch64-linux-musl,
  x86_64-windows-gnu, aarch64-macos cross-builds — all OK.

## What changed in `src/stb_image.h`

+539/−10 lines, additive and guarded; public API/ABI unchanged.

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
3. **`stbi__idct_block_avx2`** — the JPEG IDCT, two 8×8 blocks at a time (block
   A in the low 128-bit lane, block B in the high lane). A direct widening of
   `stbi__idct_simd`: every op it uses is in-lane on AVX2, so each half runs the
   exact SSE2 recipe. Bit-identical, **1.70×** SSE2 per block in isolation
   (`results/kernels.csv`, `make idct-check`). The IDCT call sites pair:
   - baseline non-interleaved (`i`,`i+1`) and progressive `finish` (`i`,`i+1`,
     all components);
   - baseline interleaved luma (`x`,`x+1` when `h>=2`, i.e. 4:2:0/4:2:2);
   - baseline interleaved consecutive single-block components (Cb+Cr in
     4:2:0/4:2:2, luma+chroma in 4:4:4), which live in different planes but
     share a stride, so the pair kernel is handed both output pointers.

   Falling back to the SSE2 kernel for leftovers, odd counts and non-AVX2 CPUs.
   The non-interleaved restart/bail path emits the pending block singly so
   corrupt-input behavior is unchanged.
4. **PNG decode** (bit-exact, no SIMD needed):
   - `stbi__create_png_image_raw` filters 8-bit rows **directly into the output**
     when `img_n==out_n` (the common `req_comp=0` case), dropping the two-row
     scratch buffer and the extra `memcpy` pass per row.
   - `stbi__parse_huffman_block` uses a **chunked LZ77 copy**: `memset` for
     `dist==1`, `memcpy` when `dist>=len`, and period-`dist` chunks when the
     match overlaps (`dist>=8`); the byte loop remains for `dist<8`. Decoded
     bytes and all error/EOF semantics are unchanged.

The header stays a single self-contained file; no new runtime dependency.

## Results

Held-out PGO (train on every corpus image except the measured 14), candidate
flags `-O3 -march=x86-64-v2 -ffp-contract=off`.

Mixed suite (14 files, `results/summary.csv`): **≈ +10% geomean** vs upstream
`-O2` (latest run +10.1%; the suite is PNG-heavy and run-to-run load shifts the
baseline). Highlights: palette PNG **+29%**, GIF **+21%**, progressive JPEG
**+19%**, 4:2:0 baseline JPEG +13–15%, 16-bit RGBA PNG +9%, 8-bit RGB PNG +8%.

PNG decode, controlled A/B vs the pre-change build (`req_comp=0`, same
compiler/flags): **+8.6% geomean** across the seven measured PNGs (palette +16%,
1-bit grayscale +12%, 16-bit grayscale +21%, 8-bit RGB +5%). On
`plasma_512.png` the IDAT/filter work drops from 51.6M to 45.3M instructions
(−12%): `stbi__create_png_image_raw` −20% (45.8%→41.6% of total) and
`stbi__do_zlib` −22% (20.4%→18.0%).

JPEG → RGBA (`req_comp=4`, where the AVX2 YCbCr kernel is active):
**≈ +13%** geomean.

IDCT standalone contribution, measured by controlled A/B against the pre-IDCT
build (same compiler/flags, no PGO):
- `req_comp=0` JPEG geomean **+7.7%**;
- `req_comp=4` JPEG geomean **+13.7%**.

The kernel itself is **1.70×** SSE2 per block (`make kernels`), which does not
depend on PGO.

Kernel isolation (`make kernels`): YCbCr AVX2 = 0.132 ns/px vs SSE2 0.214
(**1.63×**); IDCT AVX2 pair = 0.162 ns/px vs SSE2 0.275 (**1.70×**) vs scalar
1.027 (**6.35×**).

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

- **Widening the zlib fast Huffman table** (`STBI__ZFAST_BITS` 9→10) was
  measured **slower** (PNG geomean 0.925×): `stbi__zbuild_huffman` rebuilds and
  memsets the larger table per dynamic block, which outweighs the reduction in
  `stbi__zhuffman_decode_slowpath` calls. Reverted.
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

- **PNG inflate**: `stbi__zhuffman_decode` is still the largest single PNG
  block (~37% of instructions on `plasma_512.png` at `req_comp=0` after the LZ77
  improvements). Its bit-serial per-symbol cost resists easy wins — widening the
  fast table regressed (see below); a bounded two-level / multi-symbol Huffman
  table is the remaining idea.
- **PNG Paeth filtering**: the `stbi__paeth` row loop is ~21% of PNG
  instructions and is latency-bound by the `cur[k-filter_bytes]` dependency.
  The earlier pixel-at-a-time AVX2 attempt was slower; a libpng-style
  parallel-prefix/speculative approach is the untried option.
- **JPEG IDCT**: taken (see `stbi__idct_block_avx2`). Coverage is full for
  non-interleaved, progressive, 4:2:0 and 4:2:2 baseline, and 2 of 3 blocks per
  MCU in 4:4:4. The residual is the unpaired **last component (Cr) in 4:4:4**
  and the two **luma** blocks in 4:4:0 (Y is `h==1, v==2`) — not "4:4:4 luma".
  Vertical pairing (`h==1, v>=2`) would close only 4:4:0, which the corpus does
  not contain (`gen_corpus.py` emits subsampling 0/1/2 only); 4:4:4 needs
  pairing across MCUs. **Not taken**: either approach needs a stateful
  pending-pair slot (the pair kernel takes two arbitrary output pointers plus
  one stride, so any two same-stride blocks can be paired) or cross-MCU
  buffering, for an estimated **+2–3% on 4:4:4 baseline only**, at the cost of
  added state in the hot interleaved loop. Recorded here for a future pass.
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
