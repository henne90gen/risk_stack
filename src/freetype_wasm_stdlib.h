/*
 * freetype_wasm_stdlib.h
 *
 * Drop-in replacement for freetype/config/ftstdlib.h for wasm32-freestanding.
 * No libc is included. All functions are either compiler builtins, or declared
 * as externals that the Zig runtime must provide (malloc/free/realloc/qsort).
 *
 * Usage: compile freetype with
 *   -DFT_CONFIG_FILE_STDLIBH=\"freetype_wasm_stdlib.h\"
 *   -DFT_CONFIG_OPTION_DISABLE_STREAM_SUPPORT
 */

#ifndef FTSTDLIB_H_
#define FTSTDLIB_H_

#include <stdarg.h> /* va_list — provided by clang builtins */
#include <stddef.h> /* ptrdiff_t, size_t — provided by clang builtins */

#define ft_ptrdiff_t ptrdiff_t

/* -------------------------------------------------------------------------
 *  integer limits  (from compiler-defined macros, no <limits.h> needed)
 * ---------------------------------------------------------------------- */

#define FT_CHAR_BIT __CHAR_BIT__
#define FT_USHORT_MAX __UINT16_MAX__ /* assumes 16-bit short */
#define FT_INT_MAX __INT_MAX__
#define FT_INT_MIN (-__INT_MAX__ - 1)
#define FT_UINT_MAX ((__INT_MAX__) * 2U + 1U)
#define FT_LONG_MIN (-__LONG_MAX__ - 1L)
#define FT_LONG_MAX __LONG_MAX__
#define FT_ULONG_MAX ((__LONG_MAX__) * 2UL + 1UL)
#define FT_LLONG_MAX __LONG_LONG_MAX__
#define FT_LLONG_MIN (-__LONG_LONG_MAX__ - 1LL)
#define FT_ULLONG_MAX ((__LONG_LONG_MAX__) * 2ULL + 1ULL)

/* Extra limit macros used by freetype internals (e.g. sdf module). */
#define UCHAR_MAX ((unsigned char)~0)
#define SCHAR_MAX ((signed char)(__CHAR_BIT__ == 8 ? 127 : (__SCHAR_MAX__)))
#define SCHAR_MIN (-SCHAR_MAX - 1)
#ifndef CHAR_MAX
#ifdef __CHAR_UNSIGNED__
#define CHAR_MAX UCHAR_MAX
#define CHAR_MIN 0
#else
#define CHAR_MAX SCHAR_MAX
#define CHAR_MIN SCHAR_MIN
#endif
#endif
#define SHRT_MAX __SHRT_MAX__
#define SHRT_MIN (-SHRT_MAX - 1)
#define USHRT_MAX ((__SHRT_MAX__) * 2 + 1)
#define INT_MAX __INT_MAX__
#define INT_MIN (-INT_MAX - 1)
#define UINT_MAX ((__INT_MAX__) * 2U + 1U)
#define LONG_MAX __LONG_MAX__
#define LONG_MIN (-LONG_MAX - 1L)
#define ULONG_MAX ((__LONG_MAX__) * 2UL + 1UL)
#define LLONG_MAX __LONG_LONG_MAX__
#define LLONG_MIN (-LLONG_MAX - 1LL)
#define ULLONG_MAX ((__LONG_LONG_MAX__) * 2ULL + 1ULL)

/* -------------------------------------------------------------------------
 *  string / memory  (compiler builtins — no libc required)
 * ---------------------------------------------------------------------- */

#define ft_memchr(s, c, n) __builtin_memchr(s, c, n)
#define ft_memcmp(a, b, n) __builtin_memcmp(a, b, n)
#define ft_memcpy(d, s, n) __builtin_memcpy(d, s, n)
#define ft_memmove(d, s, n) __builtin_memmove(d, s, n)
#define ft_memset(d, c, n) __builtin_memset(d, c, n)
#define ft_strcat(d, s) __builtin_strcat(d, s)
#define ft_strcmp(a, b) __builtin_strcmp(a, b)
#define ft_strcpy(d, s) __builtin_strcpy(d, s)
#define ft_strlen(s) __builtin_strlen(s)
#define ft_strncmp(a, b, n) __builtin_strncmp(a, b, n)
#define ft_strncpy(d, s, n) __builtin_strncpy(d, s, n)
#define ft_strrchr(s, c) __builtin_strrchr(s, c)
#define ft_strstr(h, n) __builtin_strstr(h, n)

/* -------------------------------------------------------------------------
 *  file handling — disabled; FT_CONFIG_OPTION_DISABLE_STREAM_SUPPORT must
 *  also be defined so that FT_Stream_Open is never compiled in.
 * ---------------------------------------------------------------------- */

/* No FT_FILE, ft_fopen, ft_fclose, ft_fread, ft_fseek, ft_ftell. */

/* ft_snprintf is used in debug/trace paths only; map to __builtin_snprintf. */
#define ft_snprintf __builtin_snprintf

/* -------------------------------------------------------------------------
 *  sorting — declared extern; the Zig side must export `ft_wasm_qsort` or
 *  we provide a minimal inline implementation below.
 * ---------------------------------------------------------------------- */

extern void qsort(void* base, size_t nmemb, size_t size,
                  int (*compar)(const void*, const void*));
#define ft_qsort  qsort

/* -------------------------------------------------------------------------
 *  miscellaneous
 * ---------------------------------------------------------------------- */

extern long strtol(const char* nptr, char** endptr, int base);
#define ft_strtol  strtol

/* getenv: always returns NULL in a freestanding environment. */
static inline char *ft_wasm_getenv(const char *name) {
  (void)name;
  return (char *)0;
}
#define ft_getenv ft_wasm_getenv

/* -------------------------------------------------------------------------
 *  execution control (setjmp/longjmp)
 *
 *  wasm32 does not support __builtin_setjmp/__builtin_longjmp.
 *  We use the LLVM wasm SjLj ABI instead (-fwasm-exceptions).
 *
 *  Layout must match struct jmp_buf_impl in wasi-libc's rt.c:
 *    [0] func_invocation_id (void*)
 *    [1] label              (uint32_t, packed into a pointer slot)
 *    [2..3] arg.env / arg.val (used by __wasm_longjmp)
 * ---------------------------------------------------------------------- */

#include <stdint.h>

void __wasm_setjmp(void *env, uint32_t label, void *func_invocation_id);
uint32_t __wasm_setjmp_test(void *env, void *func_invocation_id);
void __wasm_longjmp(void *env, int val);

typedef void *ft_jmp_buf[5];

/* ft_setjmp: save context, return 0 on direct call, non-zero after longjmp */
#define ft_setjmp(b)                                                           \
  (__wasm_setjmp((b), 1, __builtin_frame_address(0)),                          \
   __wasm_setjmp_test((b), __builtin_frame_address(0)))

#define ft_longjmp(b, v) __wasm_longjmp((b), (v))

#endif /* FTSTDLIB_H_ */
