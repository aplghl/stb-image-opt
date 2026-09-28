/* Isolated bit-exactness check for the AVX2 two-block IDCT.
 *
 * For many generated coefficient blocks (A,B) it asserts:
 *   stbi__idct_block_avx2(A,B) == stbi__idct_simd(A) and stbi__idct_simd(B)
 * in both plausible output layouts (separate 8-wide buffers and one adjacent
 * 16-wide buffer). stbi__idct_simd is the reference the pair kernel mirrors, so
 * this must hold for *all* int16 inputs, including out-of-range extremes (the
 * scalar path is only guaranteed to agree within the JPEG-valid range).
 *
 * Exits nonzero on the first mismatch. Prints a one-line summary otherwise.
 *
 * usage: idct_check [iters]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

#define ITERS_DEFAULT 200000

static uint32_t rng_state = 0x12345678u;
static uint32_t rng_next(void)
{
   rng_state ^= rng_state << 13;
   rng_state ^= rng_state >> 17;
   rng_state ^= rng_state << 5;
   return rng_state;
}

static void fill_block(short *d, int mode)
{
   int i;
   switch (mode % 6) {
      case 0: // all zero
         memset(d, 0, 64 * sizeof(short));
         break;
      case 1: // DC only
         memset(d, 0, 64 * sizeof(short));
         d[0] = (short)(rng_next() >> 16);
         break;
      case 2: // sparse (few AC coefficients)
         memset(d, 0, 64 * sizeof(short));
         for (i = 0; i < 6; ++i)
            d[rng_next() & 63] = (short)(rng_next() >> 16);
         break;
      case 3: // full-range uniform
         for (i = 0; i < 64; ++i)
            d[i] = (short)(rng_next() >> 16);
         break;
      case 4: // extremes
         for (i = 0; i < 64; ++i) {
            int r = (int)(rng_next() % 3);
            d[i] = (short)(r == 0 ? 32767 : (r == 1 ? -32768 : 0));
         }
         break;
      default: // small values, realistic post-dequant range
         for (i = 0; i < 64; ++i)
            d[i] = (short)(((int)(rng_next() % 4097)) - 2048);
         break;
   }
}

int main(int argc, char **argv)
{
   int iters = argc > 1 ? atoi(argv[1]) : ITERS_DEFAULT;
   int it, mode, fail = 0;
   short d0[64], d1[64];
   /* Two output layouts: adjacent blocks in one 16-wide buffer (the common
    * case, out1 == out0 + 8, stride 16) and two separate 8-wide buffers. */
   unsigned char adj[16 * 8];
   unsigned char r0[64], r1[64];
   unsigned char s0[64], s1[64];

#if !defined(STBI_SSE2) || !defined(STBI_AVX2)
   fprintf(stderr, "idct_check requires STBI_SSE2 and STBI_AVX2\n");
   return 2;
#else
   for (it = 0; it < iters && !fail; ++it) {
      fill_block(d0, it);
      fill_block(d1, it + 3);
      mode = it % 6;

      /* reference: one block at a time via the SSE2 kernel */
      stbi__idct_simd(s0, 8, d0);
      stbi__idct_simd(s1, 8, d1);

      /* pair into two separate buffers, stride 8 */
      memset(r0, 0xAA, sizeof r0);
      memset(r1, 0xAA, sizeof r1);
      stbi__idct_block_avx2(r0, r1, 8, d0, d1);
      if (memcmp(r0, s0, 64) || memcmp(r1, s1, 64)) {
         printf("FAIL: avx2 pair (separate) != sse2 (iter %d mode %d)\n", it, mode);
         fail = 1;
         break;
      }

      /* pair into one adjacent 16-wide buffer, stride 16 */
      memset(adj, 0xAA, sizeof adj);
      stbi__idct_block_avx2(adj, adj + 8, 16, d0, d1);
      {
         int row;
         for (row = 0; row < 8; ++row) {
            if (memcmp(adj + row * 16, s0 + row * 8, 8) ||
                memcmp(adj + row * 16 + 8, s1 + row * 8, 8)) {
               printf("FAIL: avx2 pair (adjacent) != sse2 (iter %d mode %d row %d)\n", it, mode, row);
               fail = 1;
               break;
            }
         }
      }
   }

   if (!fail) {
      printf("PASS: idct avx2 pair bit-exact vs sse2 (%d iters)\n", iters);
      return 0;
   }
   return 1;
#endif
}
