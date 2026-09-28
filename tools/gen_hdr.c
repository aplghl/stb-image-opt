/* Generate Radiance .hdr test images with upstream stb_image_write.
 * usage: gen_hdr <outdir>
 */
#include <stdio.h>
#include <math.h>
#include <stdlib.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

static void emit(const char *dir, const char *name, int w, int h, int comp,
                 const float *px)
{
   char path[1024];
   snprintf(path, sizeof path, "%s/%s", dir, name);
   if (!stbi_write_hdr(path, w, h, comp, px)) {
      fprintf(stderr, "failed: %s\n", path);
      exit(1);
   }
   printf("%s\n", path);
}

int main(int argc, char **argv)
{
   const char *dir = argc > 1 ? argv[1] : "corpus";
   const int W = 256, H = 192;
   float *rgb = (float *)malloc((size_t)W * H * 3 * sizeof(float));
   float *g = (float *)malloc((size_t)W * H * sizeof(float));
   int x, y, c;

   for (y = 0; y < H; ++y) {
      for (x = 0; x < W; ++x) {
         float u = (float)x / (W - 1), v = (float)y / (H - 1);
         float e = powf(2.0f, 20.0f * (u - 0.5f));   /* huge dynamic range */
         float r = e * sinf(u * 6.283f), gg = e * 0.5f * cosf(v * 6.283f), b = e * u;
         rgb[(y * W + x) * 3 + 0] = r;
         rgb[(y * W + x) * 3 + 1] = gg;
         rgb[(y * W + x) * 3 + 2] = b;
         g[y * W + x] = e * (u - v);
      }
   }
   emit(dir, "hdr_range.hdr", W, H, 3, rgb);
   emit(dir, "hdr_gray.hdr", W, H, 1, g);

   /* smooth low-dynamic-range variant, all channels */
   for (y = 0; y < H; ++y)
      for (x = 0; x < W; ++x)
         for (c = 0; c < 3; ++c)
            rgb[(y * W + x) * 3 + c] = 0.5f + 0.4f * sinf((x + y + c) * 0.05f);
   emit(dir, "hdr_smooth.hdr", W, H, 3, rgb);

   free(rgb);
   free(g);
   return 0;
}
