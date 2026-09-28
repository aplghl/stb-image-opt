/* Per-kernel microbenchmarks. Includes the implementation so the static
 * kernels are directly callable.
 *
 * usage: kernbench <kernel> [n] [iters]
 *   kernel: ycbcr_scalar | ycbcr_sse2 | ycbcr_avx2
 * output: name,n,iters,ns_per_pixel
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

static double now_s(void)
{
   struct timespec ts;
   clock_gettime(CLOCK_MONOTONIC, &ts);
   return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

#if defined(__x86_64__) || defined(__i386__)
static void *xaligned(size_t n) { void *p; if (posix_memalign(&p, 64, n)) return NULL; return p; }
#else
static void *xaligned(size_t n) { return malloc(n); }
#endif

int main(int argc, char **argv)
{
   const char *k = argc > 1 ? argv[1] : "ycbcr_avx2";
   int n = argc > 2 ? atoi(argv[2]) : 4096;
   int iters = argc > 3 ? atoi(argv[3]) : 20000;
   stbi_uc *y = xaligned(n), *cb = xaligned(n), *cr = xaligned(n), *out = xaligned((size_t)n * 4);
   int i, it;
   double t0, t1, best = 1e300;

   if (!y || !cb || !cr || !out) return 2;
   for (i = 0; i < n; ++i) { y[i] = (stbi_uc)(i * 7); cb[i] = (stbi_uc)(i * 13 + 3); cr[i] = (stbi_uc)(i * 29 + 5); }

   for (it = 0; it < 5; ++it) {
      t0 = now_s();
      if (strcmp(k, "ycbcr_scalar") == 0) {
         for (i = 0; i < iters; ++i) stbi__YCbCr_to_RGB_row(out, y, cb, cr, n, 4);
      } else if (strcmp(k, "ycbcr_sse2") == 0) {
#ifdef STBI_SSE2
         for (i = 0; i < iters; ++i) stbi__YCbCr_to_RGB_simd(out, y, cb, cr, n, 4);
#else
         fprintf(stderr, "no SSE2\n"); return 2;
#endif
      } else if (strcmp(k, "ycbcr_avx2") == 0) {
#ifdef STBI_AVX2
         for (i = 0; i < iters; ++i) stbi__YCbCr_to_RGB_avx2(out, y, cb, cr, n, 4);
#else
         fprintf(stderr, "no AVX2\n"); return 2;
#endif
      } else { fprintf(stderr, "unknown kernel %s\n", k); return 2; }
      t1 = now_s();
      if (t1 - t0 < best) best = t1 - t0;
   }

   printf("%s,%d,%d,%.5f\n", k, n, iters, best * 1e9 / ((double)n * iters));
   free(y); free(cb); free(cr); free(out);
   return 0;
}
