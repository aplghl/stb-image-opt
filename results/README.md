# results

Benchmark CSVs from the fork. Timings are machine-specific (Intel i7-14700F,
WSL2, clang 23.1.2) and load-sensitive; treat the ranking as the signal.
Correctness is verified separately (`make verify`, `make sanitize`) and is not
machine-specific.

| file | generator | contents |
| ---- | --------- | -------- |
| `summary.csv` | `make bench-vs-upstream` | **headline table**: per-file upstream `-O2` vs fork (PGO, held-out), and the geomean speedup |
| `upstream_o2.csv` | `make bench-vs-upstream` | baseline throughput, upstream header at `-O2`, `req_comp=0` |
| `fork_pgo.csv` | `make bench-vs-upstream` | fork throughput, `-O3 -march=x86-64-v2 -ffp-contract=off` + held-out PGO |
| `up4.csv` | `REQ=4 bash harness/bench.sh up4 upstream -O2` | baseline, `req_comp=4` (RGBA path) |
| `fork4.csv` | `REQ=4 PGO_DIR=... bash harness/bench.sh fork4 src ...` | fork, `req_comp=4` |
| `kernels.csv` | `make kernels` | isolated kernels: YCbCr and IDCT scalar / SSE2 / AVX2 ns per sample |

Columns for `up*`/`fork*`: `file,bytes,w,h,comp,req,iters,ns_per_decode,`
`ns_per_pixel,cycles_per_pixel,Mpixel_per_s`.

Key numbers: mixed-suite geomean **≈ +5%** (`summary.csv`); JPEG→RGBA geomean
**≈ +13%** (`up4` vs `fork4`); AVX2 YCbCr **1.59×** SSE2 and AVX2 IDCT
**1.81×** SSE2 per block (`kernels.csv`).
