/* Single translation unit for the prebuilt static library. Public API/ABI are
 * the original STBIDEF prototypes; the runtime AVX2 dispatch keeps the library
 * portable across x86-64 CPUs. */
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
