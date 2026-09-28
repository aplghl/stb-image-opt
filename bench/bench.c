/* Decode throughput benchmark for stb_image.
 *
 * usage: bench <file> [budget_s] [repeats] [req_comp]
 *   budget_s : target seconds of decode per repeat (default 0.2)
 *   repeats  : number of repeats, min is reported (default 5)
 *   req_comp : 0..4 (default 0 = native channels)
 *
 * output (CSV): file,bytes,w,h,comp,req,iters,ns_per_decode,ns_per_pixel,
 *               cycles_per_pixel,Mpixel_per_s
 *
 * Pin with taskset for stable numbers.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdint.h>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#if defined(__x86_64__) || defined(__i386__)
static inline uint64_t rdtsc(void)
{
   unsigned lo, hi;
   __asm__ __volatile__ ("rdtsc" : "=a"(lo), "=d"(hi));
   return ((uint64_t)hi << 32) | lo;
}
#else
static inline uint64_t rdtsc(void) { return 0; }
#endif

static double now_s(void)
{
   struct timespec ts;
   clock_gettime(CLOCK_MONOTONIC, &ts);
   return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

static unsigned char *read_file(const char *path, size_t *len)
{
   FILE *f = fopen(path, "rb");
   unsigned char *buf;
   long n;
   if (!f) return NULL;
   fseek(f, 0, SEEK_END);
   n = ftell(f);
   rewind(f);
   buf = (unsigned char *)malloc((size_t)n);
   if (buf && n > 0 && fread(buf, 1, (size_t)n, f) != (size_t)n) { free(buf); buf = NULL; }
   fclose(f);
   *len = (size_t)n;
   return buf;
}

int main(int argc, char **argv)
{
   const char *path;
   double budget = 0.2;
   int repeats = 5, req = 0;
   size_t len = 0;
   unsigned char *buf;
   int w = 0, h = 0, comp = 0;
   double total_px, best_ns = 1e300;
   uint64_t best_cyc = 0;
   long best_iters = 0;
   int pass;

   if (argc < 2) { fprintf(stderr, "usage: %s <file> [budget] [repeats] [req_comp]\n", argv[0]); return 2; }
   path = argv[1];
   if (argc > 2) budget = atof(argv[2]);
   if (argc > 3) repeats = atoi(argv[3]);
   if (argc > 4) req = atoi(argv[4]);

   buf = read_file(path, &len);
   if (!buf) { fprintf(stderr, "cannot read %s\n", path); return 2; }
   if (!stbi_info_from_memory(buf, (int)len, &w, &h, &comp)) {
      fprintf(stderr, "not an image: %s\n", path); free(buf); return 1;
   }
   total_px = (double)w * (double)h;

   for (pass = 0; pass < repeats; ++pass) {
      uint64_t c0, c1;
      double t0, t1, per;
      long iters, i;
      double t_single;

      stbi_uc *im = stbi_load_from_memory(buf, (int)len, &w, &h, &comp, req ? req : 0);
      if (!im) { fprintf(stderr, "decode failed: %s\n", path); free(buf); return 1; }
      stbi_image_free(im);

      t0 = now_s();
      im = stbi_load_from_memory(buf, (int)len, &w, &h, &comp, req ? req : 0);
      t1 = now_s();
      stbi_image_free(im);
      t_single = t1 - t0;
      if (t_single <= 0) t_single = 1e-6;

      iters = (long)(budget / t_single);
      if (iters < 1) iters = 1;
      if (iters > 2000000) iters = 2000000;

      c0 = rdtsc(); t0 = now_s();
      for (i = 0; i < iters; ++i) {
         im = stbi_load_from_memory(buf, (int)len, &w, &h, &comp, req ? req : 0);
         if (!im) { fprintf(stderr, "decode failed mid-bench\n"); free(buf); return 1; }
         stbi_image_free(im);
      }
      t1 = now_s(); c1 = rdtsc();

      per = (t1 - t0) / (double)iters;
      if (per < best_ns) {
         best_ns = per;
         best_iters = iters;
         best_cyc = (c1 - c0) / (uint64_t)iters;
      }
   }

   printf("%s,%zu,%d,%d,%d,%d,%ld,%.1f,%.4f,%.3f,%.2f\n",
          path, len, w, h, comp, req, best_iters,
          best_ns * 1e9, best_ns * 1e9 / total_px,
          (double)best_cyc / total_px, total_px / best_ns / 1e6);
   free(buf);
   return 0;
}
