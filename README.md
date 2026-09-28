# stb-image-opt

[![CI](https://github.com/aplghl/stb-image-opt/actions/workflows/ci.yml/badge.svg)](https://github.com/aplghl/stb-image-opt/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/aplghl/stb-image-opt)](https://github.com/aplghl/stb-image-opt/releases/latest)
[![License: MIT OR Unlicense](https://img.shields.io/badge/license-MIT%20OR%20Unlicense-blue.svg)](#license)

A performance fork of [stb_image](https://github.com/nothings/stb) (`stb_image.h`
v2.30) with **runtime-dispatched AVX2** fast paths (JPEG IDCT and YCbCr→RGB), a
bit-exact PNG decode speedup, a reproducible PGO build recipe, and a bit-exact
differential harness. Optimize once, and every consumer of the header or the
prebuilt library benefits — with **no source or build changes** and **identical
decoded output**.

- **Upstream base:** `nothings/stb` @ `2c980bb` (`stb_image.h` v2.30), vendored
  in `upstream/` as the pristine oracle.
- **License:** MIT OR Unlicense, same as upstream. See [License](#license).
- **Scope:** `stb_image.h` only (the read/decoding side).
- **Status:** exact build is bit-identical to upstream; the AVX2 paths are selected
  at runtime and fall back to SSE2/scalar on older CPUs.
- **Downloads:** prebuilt static libraries for Linux (glibc/musl), Linux ARM64
  and Windows are attached to [releases](https://github.com/aplghl/stb-image-opt/releases)
  — see [Prebuilt releases](#prebuilt-releases).

Only **`src/stb_image.h`** is modified: +539/−10 lines, all additive and guarded.
The public API, structs, ABI and default behavior are unchanged.

## Results

Stock upstream is compiled the way consumers compile it (`-O2`). The fork is
compiled with `-O3 -march=x86-64-v2 -ffp-contract=off` + multi-workload **PGO**
trained on a *held-out* corpus. Intel i7-14700F (Raptor Lake), clang 23.1.2,
WSL2. Reproduce with `make bench-vs-upstream`.

| workload | speedup vs upstream `-O2` |
| --- | --- |
| Mixed suite (`results/summary.csv`) | **≈ +10%** geomean |
| PNG decode (isolated A/B, `req_comp=0`) | **+8.6%** geomean |
| palette PNG | **+29%** |
| GIF decode | **+21%** |
| progressive JPEG | **+19%** |
| JPEG → RGBA (`req_comp=4`) | **≈ +13%** geomean |
| AVX2 YCbCr kernel vs SSE2 (isolated) | **1.63×** |
| AVX2 IDCT pair kernel vs SSE2 (isolated) | **1.70×** |

The IDCT pair kernel adds **≈ +8%** on `req_comp=0` and **≈ +14%** on
`req_comp=4` JPEG decoding (controlled A/B vs the pre-IDCT build, same
compiler/flags), on top of the PGO and YCbCr gains. It is the largest JPEG
compute step and, unlike the YCbCr kernel, accelerates every output channel
count.

PNG decoding adds **+8.6%** (isolated A/B, `req_comp=0`): 8-bit rows are
filtered directly into the output (no scratch buffer + copy), and the zlib LZ77
copy is chunked instead of byte-at-a-time. Both are bit-exact and independent
of SIMD.

The exact build is **bit-identical** to upstream on the whole corpus
(`upstream/tests/pngsuite` + generated corpus: ~12,300 checks across
`stbi_load` `req_comp` 0–4, `stbi_load_16`, `stbi_loadf`, GIF frames and
`stbi_info`), on every dispatch path (auto/AVX2/SSE2/scalar) and with clang,
gcc and `zig cc`. No fast-math: the build stays exact by default.

Numbers are single-machine and load-sensitive; see `NOTES.md` for variance.

## Usage

### Option 1 — drop-in header

Replace your `stb_image.h` with `src/stb_image.h`. Nothing else changes; keep
your existing

```c
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
```

This gets you the AVX2 path plus the recommended rewrite only if *you* opt into
the PGO flags below. If you just want a faster decoder without touching flags,
use Option 2.

### Option 2 — prebuilt static library

Build once with the recommended flags/profile and link it. The public prototypes
are the original `STBIDEF` ones, so declare them by including the header
*without* `STB_IMAGE_IMPLEMENTATION`.

```sh
# build the optimized library (exact, bit-identical)
scripts/build_opt.sh exact
# or with multi-workload PGO
PGO=1 scripts/build_opt.sh exact

# or via Zig (also supports cross-targets)
zig build -Doptimize=ReleaseFast
zig build -Doptimize=ReleaseFast -Dtarget=aarch64-linux-musl
```

Then link `build/lib_exact/libstb_image_opt.a` (or
`zig-out/lib/libstb-image-opt.a`) and use the normal API:

```c
#include "stb_image.h"          /* declarations only */
/* ... stbi_load(...), stbi_image_free(...) ... */
```

#### Prebuilt releases

Tagged releases attach ready-to-link tarballs (built with
`zig build -Doptimize=ReleaseFast`; the AVX2 path is runtime-dispatched, so one
x86-64 binary runs on AVX2 and non-AVX2 CPUs alike):

| Asset | Platform | ABI / notes |
| --- | --- | --- |
| `stb-image-opt-x86_64-linux-gnu.tar.gz` | Linux x86-64 | glibc — link with `-lm` |
| `stb-image-opt-x86_64-linux-musl.tar.gz` | Linux x86-64 | musl, static |
| `stb-image-opt-aarch64-linux-musl.tar.gz` | Linux ARM64 | musl, static |
| `stb-image-opt-x86_64-windows-gnu.tar.gz` | Windows x86-64 | MinGW — library is `stb-image-opt.lib` |

Each tarball extracts to `<triple>/` and contains:

- `stb_image.h` — identical to `src/stb_image.h` in every tarball.
- the static library (`libstb-image-opt.a`, or `stb-image-opt.lib` on Windows),
  exporting the original `stbi_*` symbols.

Include the header **without** `STB_IMAGE_IMPLEMENTATION`, link the library (and
`-lm` on glibc Linux), and call the normal API:

```sh
cc app.c -I x86_64-linux-gnu x86_64-linux-gnu/libstb-image-opt.a -lm
```

Not shipped — build from source instead: **macOS**
(`zig build -Dtarget=aarch64-macos`) and the **PGO/exact** variants
(`scripts/build_opt.sh`, `PGO=1 scripts/build_opt.sh`).

## What changed

Two runtime-dispatched AVX2 kernels, plus a bit-exact PNG decode speedup:

1. `stbi__YCbCr_to_RGB_avx2` — a 16-pixel-wide AVX2 YCbCr→RGB kernel (used for
   4-channel output, the same case the existing SSE2 path accelerates). Each
   lane reproduces the SSE2 integer math and the SSE2 pack/interleave
   byte-for-byte, so the output is bit-identical; only the interleave is widened
   to true 256-bit using two cross-lane permutes.

2. `stbi__idct_block_avx2` — the JPEG IDCT, processing **two 8×8 blocks at once**
   (one per 128-bit lane). It is a direct widening of `stbi__idct_simd`: every
   operation it uses (`madd`, `unpacklo/hi`, `packs`, `packus`, `srai`) is
   in-lane on AVX2, so each half runs the exact SSE2 recipe and is byte-for-byte
   identical. Callers pair adjacent blocks in the baseline non-interleaved and
   progressive `finish` loops, horizontally adjacent luma blocks in the baseline
   interleaved loop, and consecutive single-block components (Cb+Cr in
   4:2:0/4:2:2, luma+chroma in 4:4:4), falling back to the SSE2 kernel for
   leftovers.

3. **PNG decode** — two bit-exact, no-SIMD improvements:
   `stbi__create_png_image_raw` filters 8-bit rows directly into the output when
   `img_n==out_n` (dropping the scratch row buffer and the copy), and the zlib
   LZ77 copy in `stbi__parse_huffman_block` is chunked (`memset` for `dist==1`,
   wide copies otherwise) instead of byte-at-a-time.

Dispatch is added cleanly on top of stb's existing model:

```c
#ifdef STBI_AVX2
   if (stbi__avx2_available()) {
      j->YCbCr_to_RGB_kernel  = stbi__YCbCr_to_RGB_avx2;
      j->idct_block_pair_kernel = stbi__idct_block_avx2; // NULL otherwise
   }
#endif
```

`stbi__avx2_available()` is a self-contained CPUID + `XGETBV` check (no libgcc
`__cpu_model` dependency, so `zig cc` links). AVX2 kernels are separate
functions carrying `__attribute__((target("avx2")))`, so the rest of the
translation unit stays baseline and one binary runs on every x86-64 CPU.

For differential testing the path can be pinned with `STBI_FORCE_AVX2`,
`STBI_FORCE_SSE2`, or `STBI_FORCE_SCALAR`.

## Verifying and benchmarking

The test harness needs only a C compiler (`clang` or `gcc`) and the committed
corpus — no other setup.

```sh
make verify            # all dispatch paths bit-exact vs pristine oracle
make verify-portable   # SSE-only / no-SIMD / ONLY_* / C++ / zig cross-targets
make idct-check        # isolated AVX2 two-block IDCT vs SSE2 reference
make sanitize          # ASan+UBSan over corpus, truncations, mutations
make fuzz ARGS=120     # libFuzzer
make bench-vs-upstream # head-to-head vs upstream -O2 -> results/summary.csv
make kernels           # per-kernel microbench -> results/kernels.csv
```

The **hermetic toolchain is optional** — it pins exact compiler versions
(clang 23, Zig 0.16, ISPC 1.31, valgrind) for reproducible local work and
cross-builds, and installs entirely in user space (no sudo):

```sh
scripts/bootstrap_toolchain.sh all
source scripts/env.sh
```

`upstream/` is the pristine oracle; the candidate is always `src/`.

## Compatibility

| configuration | result |
| --- | --- |
| x86-64 (SSE2 baseline), no AVX2 CPU | bit-exact, uses SSE2/scalar |
| x86-64-v3 (AVX2) | bit-exact, uses AVX2 |
| `-DSTBI_NO_SIMD`, `-DSTBI_FORCE_SCALAR` | bit-exact |
| `-DSTBI_ONLY_PNG` / `-DSTBI_ONLY_JPEG` / format toggles | bit-exact |
| `-DSTBI_NO_STDIO` | bit-exact |
| C and C++ | compiles clean |
| gcc, clang, `zig cc` | bit-exact |
| aarch64-linux-musl, x86_64-windows-gnu, aarch64-macos | cross-compiles |

## Repository layout

```
src/stb_image.h      optimized header (the fork)
upstream/            pristine nothings/stb (oracle, never edited)
lib/stb_image.c      TU for the prebuilt static library
tools/               decode_dump (differential), idct_check, gen_hdr, stbi_fuzz (libFuzzer)
harness/             diff, dispatch, portable, idct_check, sanitize, fuzz, bench*, kernbench
bench/               bench.c (throughput), kernbench.c (kernels)
corpus/              deterministic generated images + generator
scripts/             bootstrap_toolchain, env, build_opt
build.zig Makefile   multi-target / convenience targets
results/             benchmark CSVs (see results/README.md)
NOTES.md             method, full results, rejected experiments, remaining headroom
```

## License

This fork is distributed under the same terms as upstream `stb`: a choice of the
[MIT License](LICENSE) or the public-domain
[Unlicense](LICENSE), whichever you prefer. The modifications in this repository
are released under those same terms.

Based on [stb](https://github.com/nothings/stb) by Sean Barrett and
contributors. This is an unofficial fork and is **not endorsed by the upstream
author**. The PNG Paeth predictor referenced in the rejected experiment follows
the standard algorithm also implemented by [libpng](http://www.libpng.org/); the
code here is an independent implementation.
