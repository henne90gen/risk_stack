/*
 * freetype_wasm_stubs.c
 *
 * Provides all symbols that freetype references but that are absent in a
 * wasm32-freestanding build:
 *
 *  - C string functions (compiler builtins don't always emit inline code)
 *  - malloc / free / realloc  (extern decls — the Zig runtime exports these)
 *  - FT_Gzip_Uncompress / FT_Stream_OpenGzip / FT_Stream_OpenLZW  (stubs)
 *  - FT_Trace_Disable / FT_Trace_Enable  (no-ops replacing ftdebug.c)
 */

#include <stddef.h>
#include <stdint.h>

/* ft2build.h + internal headers are safe here because FT2_BUILD_LIBRARY
 * is defined via the compiler flags for this translation unit. */
#include <ft2build.h>
#include FT_CONFIG_CONFIG_H
#include <freetype/fttypes.h>
#include <freetype/internal/ftstream.h>
#include <freetype/internal/ftdebug.h>

/* =========================================================================
 * String functions — needed because __builtin_* don't always inline
 * ====================================================================== */

int strcmp(const char *a, const char *b) {
  while (*a && *a == *b) { a++; b++; }
  return (unsigned char)*a - (unsigned char)*b;
}

int strncmp(const char *a, const char *b, size_t n) {
  while (n && *a && *a == *b) { a++; b++; n--; }
  if (!n) return 0;
  return (unsigned char)*a - (unsigned char)*b;
}

char *strcpy(char *dst, const char *src) {
  char *d = dst;
  while ((*d++ = *src++));
  return dst;
}

char *strncpy(char *dst, const char *src, size_t n) {
  char *d = dst;
  while (n && (*d++ = *src++)) n--;
  while (n--) *d++ = '\0';
  return dst;
}

char *strcat(char *dst, const char *src) {
  char *d = dst;
  while (*d) d++;
  while ((*d++ = *src++));
  return dst;
}

char *strrchr(const char *s, int c) {
  const char *last = NULL;
  do { if (*s == (char)c) last = s; } while (*s++);
  return (char *)last;
}

char *strstr(const char *haystack, const char *needle) {
  if (!*needle) return (char *)haystack;
  for (; *haystack; haystack++) {
    const char *h = haystack, *n = needle;
    while (*h && *n && *h == *n) { h++; n++; }
    if (!*n) return (char *)haystack;
  }
  return NULL;
}

void *memchr(const void *s, int c, size_t n) {
  const unsigned char *p = s;
  while (n--) {
    if (*p == (unsigned char)c) return (void *)p;
    p++;
  }
  return NULL;
}

/* =========================================================================
 * Memory allocation — provided by the Zig runtime as wasm exports.
 * ====================================================================== */

extern void *malloc(size_t size);
extern void  free(void *ptr);
extern void *realloc(void *ptr, size_t size);

/* =========================================================================
 * FreeType gzip/lzw stubs
 *
 * sfnt.c references these even when the gzip/lzw modules are not compiled.
 * We avoid including <freetype/fterrors.h> here (it uses X-macros that
 * require FT2_BUILD_LIBRARY context) and use the raw error code instead.
 * FT_Err_Unimplemented_Feature == 0x07 per fterrdef.h.
 * ====================================================================== */

#define FT_ERR_UNIMPLEMENTED 0x07

FT_Error FT_Gzip_Uncompress(FT_Memory memory, FT_Byte *output,
                             FT_ULong *output_len, const FT_Byte *input,
                             FT_ULong input_len) {
  (void)memory; (void)output; (void)output_len; (void)input; (void)input_len;
  return FT_ERR_UNIMPLEMENTED;
}

FT_Error FT_Stream_OpenGzip(FT_Stream stream, FT_Stream source) {
  (void)stream; (void)source;
  return FT_ERR_UNIMPLEMENTED;
}

FT_Error FT_Stream_OpenLZW(FT_Stream stream, FT_Stream source) {
  (void)stream; (void)source;
  return FT_ERR_UNIMPLEMENTED;
}

/* =========================================================================
 * FT_Trace_Disable / FT_Trace_Enable — no-ops (replaces ftdebug.c)
 * ====================================================================== */

FT_BASE_DEF(void) FT_Trace_Disable(void) {}
FT_BASE_DEF(void) FT_Trace_Enable(void)  {}
