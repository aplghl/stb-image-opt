/* libFuzzer entry point for the optimized stb_image fork.
 * Exercises info + every output channel count + 16-bit, so the runtime
 * AVX2/SSE2/scalar paths are all reachable from the fuzzer.
 */
#include <stdint.h>
#include <stdlib.h>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
   int x, y, comp;
   unsigned char *img;

   if (size < 1 || size > (size_t)1 << 26) return 0; /* <=64 MiB */

   if (!stbi_info_from_memory(data, (int)size, &x, &y, &comp)) return 0;
   if (y && x > (80000000 / 4) / y) return 0;

   img = stbi_load_from_memory(data, (int)size, &x, &y, &comp, 4);
   stbi_image_free(img);
   img = stbi_load_from_memory(data, (int)size, &x, &y, &comp, 0);
   stbi_image_free(img);
   img = stbi_load_from_memory(data, (int)size, &x, &y, &comp, 1);
   stbi_image_free(img);

   {
      stbi_us *u16 = stbi_load_16_from_memory(data, (int)size, &x, &y, &comp, 4);
      stbi_image_free(u16);
   }
#ifndef STBI_NO_LINEAR
   {
      float *f = stbi_loadf_from_memory(data, (int)size, &x, &y, &comp, 4);
      stbi_image_free(f);
   }
#endif
   return 0;
}
