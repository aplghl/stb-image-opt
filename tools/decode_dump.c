/* decode_dump - decode an image with stb_image and write the exact decoded
 * bytes to stdout, for bit-exact differential testing against the pristine
 * upstream oracle.
 *
 * usage:
 *   decode_dump <file> <req_comp> <variant>   variant = u8 | u16 | f32
 *   decode_dump --gif   <file>                all frames, req_comp = 4
 *   decode_dump --info  <file>                stbi_info metadata only
 *
 * stdout: a fixed little-endian header followed by the raw pixel bytes.
 *   u8/u16/f32 : u32 w, u32 h, u32 out_channels, then w*h*out*bytes pixels
 *   --gif      : u32 w, u32 h, u32 frames, u32 out_channels, pixels per frame
 *   --info     : u32 w, u32 h, u32 channels
 *
 * exit 0 on success (bytes written), 1 on decode failure.
 *
 * The whole stream is compared with cmp(1) by harness/diff.sh, so any change in
 * dimensions, channel count or a single pixel byte is detected.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

static void put_u32(FILE *f, unsigned v)
{
   unsigned char b[4];
   b[0] = (unsigned char)(v & 0xff);
   b[1] = (unsigned char)((v >> 8) & 0xff);
   b[2] = (unsigned char)((v >> 16) & 0xff);
   b[3] = (unsigned char)((v >> 24) & 0xff);
   fwrite(b, 1, 4, f);
}

static unsigned char *read_file(const char *path, size_t *out_len)
{
   FILE *f = fopen(path, "rb");
   unsigned char *buf;
   long n;
   if (!f) return NULL;
   if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
   n = ftell(f);
   if (n < 0) { fclose(f); return NULL; }
   rewind(f);
   buf = (unsigned char *)malloc((size_t)n ? (size_t)n : 1);
   if (!buf) { fclose(f); return NULL; }
   if (n > 0 && fread(buf, 1, (size_t)n, f) != (size_t)n) { free(buf); fclose(f); return NULL; }
   fclose(f);
   *out_len = (size_t)n;
   return buf;
}

int main(int argc, char **argv)
{
   const char *mode, *path;
   size_t len = 0;
   unsigned char *buf;
   int w = 0, h = 0, comp = 0;

   if (argc < 3) {
      fprintf(stderr, "usage: %s <file> <req_comp> <u8|u16|f32> | --gif <file> | --info <file>\n", argv[0]);
      return 2;
   }

   if (strcmp(argv[1], "--gif") == 0 || strcmp(argv[1], "--info") == 0) {
      mode = argv[1];
      path = argv[2];
   } else {
      mode = "load";
      path = argv[1];
      if (argc < 4) { fprintf(stderr, "missing variant\n"); return 2; }
   }

   buf = read_file(path, &len);
   if (!buf) { fprintf(stderr, "cannot read %s\n", path); return 2; }

   if (strcmp(mode, "--info") == 0) {
      int ok = stbi_info_from_memory(buf, (int)len, &w, &h, &comp);
      free(buf);
      if (!ok) return 1;
      put_u32(stdout, (unsigned)w);
      put_u32(stdout, (unsigned)h);
      put_u32(stdout, (unsigned)comp);
      if (fflush(stdout) != 0) return 2;
      return 0;
   }

   if (strcmp(mode, "--gif") == 0) {
#if !defined(STBI_NO_GIF)
      int frames = 0, *delays = NULL;
      stbi_uc *data = stbi_load_gif_from_memory(buf, (int)len, &delays, &w, &h, &frames, &comp, 4);
      free(buf);
      if (!data) return 1;
      put_u32(stdout, (unsigned)w);
      put_u32(stdout, (unsigned)h);
      put_u32(stdout, (unsigned)frames);
      put_u32(stdout, 4);
      fwrite(data, 1, (size_t)w * (size_t)h * 4u * (size_t)frames, stdout);
      stbi_image_free(data);
      free(delays);
      if (fflush(stdout) != 0) return 2;
      return 0;
#else
      free(buf);
      return 1;
#endif
   }

   {
      int req = atoi(argv[2]);
      const char *variant = argv[3];
      int outn;
      size_t nbytes;

      if (req < 0 || req > 4) { free(buf); fprintf(stderr, "bad req_comp\n"); return 2; }
      if (strcmp(variant, "u8") == 0) {
         stbi_uc *data = stbi_load_from_memory(buf, (int)len, &w, &h, &comp, req);
         free(buf);
         if (!data) return 1;
         outn = req ? req : comp;
         nbytes = (size_t)w * (size_t)h * (size_t)outn;
         put_u32(stdout, (unsigned)w); put_u32(stdout, (unsigned)h); put_u32(stdout, (unsigned)outn);
         fwrite(data, 1, nbytes, stdout);
         stbi_image_free(data);
      } else if (strcmp(variant, "u16") == 0) {
         stbi_us *data = stbi_load_16_from_memory(buf, (int)len, &w, &h, &comp, req);
         free(buf);
         if (!data) return 1;
         outn = req ? req : comp;
         nbytes = (size_t)w * (size_t)h * (size_t)outn * 2u;
         put_u32(stdout, (unsigned)w); put_u32(stdout, (unsigned)h); put_u32(stdout, (unsigned)outn);
         fwrite(data, 1, nbytes, stdout);
         stbi_image_free(data);
      } else if (strcmp(variant, "f32") == 0) {
#if !defined(STBI_NO_LINEAR)
         float *data = stbi_loadf_from_memory(buf, (int)len, &w, &h, &comp, req);
         free(buf);
         if (!data) return 1;
         outn = req ? req : comp;
         nbytes = (size_t)w * (size_t)h * (size_t)outn * sizeof(float);
         put_u32(stdout, (unsigned)w); put_u32(stdout, (unsigned)h); put_u32(stdout, (unsigned)outn);
         fwrite(data, 1, nbytes, stdout);
         stbi_image_free(data);
#else
         free(buf);
         return 1;
#endif
      } else {
         free(buf);
         fprintf(stderr, "unknown variant %s\n", variant);
         return 2;
      }
      if (fflush(stdout) != 0) return 2;
      return 0;
   }
}
