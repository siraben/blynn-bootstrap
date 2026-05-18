#include <stdio.h>
#include <stdlib.h>

enum {
  OP_HALT = 0,
  OP_CONST = 1,
  OP_C_CALL = 14
};

static FILE *out_file;
static long out_len;
static long parse_next;

static void die(const char *msg)
{
  fputs("mlc-seed: ", stderr);
  fputs(msg, stderr);
  fputc('\n', stderr);
  exit(1);
}

static char *read_file(const char *path, long *len_out)
{
  FILE *file = fopen(path, "rb");
  char *buf = 0;
  long len = 0;
  long cap = 0;
  int c;
  if (!file) die("cannot open input file");
  c = fgetc(file);
  while (c != EOF) {
    if (len == cap) {
      char *next;
      if (cap == 0) cap = 4096;
      else cap = cap * 2;
      next = (char *)realloc(buf, cap + 1);
      if (!next) die("out of memory");
      buf = next;
    }
    buf[len] = (char)c;
    len = len + 1;
    c = fgetc(file);
  }
  fclose(file);
  if (buf == 0) {
    buf = (char *)malloc(1);
    if (!buf) die("out of memory");
  }
  buf[len] = 0;
  *len_out = len;
  return buf;
}

static int is_space(int c)
{
  return c == ' ' || c == '\n' || c == '\r' || c == '\t';
}

static long skip_space(char *src, long len, long i)
{
  while (i < len && is_space(src[i])) i = i + 1;
  return i;
}

static int is_ident_char(int c)
{
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

static int match_write_byte(char *src, long len, long i)
{
  if (i + 10 > len) return 0;
  if (src[i] != 'w') return 0;
  if (src[i + 1] != 'r') return 0;
  if (src[i + 2] != 'i') return 0;
  if (src[i + 3] != 't') return 0;
  if (src[i + 4] != 'e') return 0;
  if (src[i + 5] != '_') return 0;
  if (src[i + 6] != 'b') return 0;
  if (src[i + 7] != 'y') return 0;
  if (src[i + 8] != 't') return 0;
  if (src[i + 9] != 'e') return 0;
  if (i + 10 < len && is_ident_char(src[i + 10])) return 0;
  return 1;
}

static long parse_int_at(char *src, long len, long i)
{
  long sign = 1;
  long out = 0;
  int seen = 0;
  long p = skip_space(src, len, i);
  if (p < len && src[p] == '-') {
    sign = -1;
    p = p + 1;
  }
  while (p < len && src[p] >= '0' && src[p] <= '9') {
    out = out * 10 + (src[p] - '0');
    seen = 1;
    p = p + 1;
  }
  if (!seen) die("expected integer after write_byte");
  parse_next = p;
  return out * sign;
}

static void emit_byte(int c)
{
  fputc(c, out_file);
  out_len = out_len + 1;
}

static long low_byte(long x)
{
  long q = x / 256;
  long out = x - q * 256;
  if (out < 0) out = out + 256;
  return out;
}

static void emit_u32(long x)
{
  emit_byte((int)low_byte(x));
  emit_byte((int)low_byte(x / 256));
  emit_byte((int)low_byte(x / 65536));
  emit_byte((int)low_byte(x / 16777216));
}

static void emit_const_write(long n)
{
  emit_byte(OP_CONST);
  emit_u32(n);
  emit_byte(OP_C_CALL);
  emit_u32(1);
  emit_u32(1);
}

static long count_writes(char *src, long src_len)
{
  long i = 0;
  long writes = 0;
  while (i < src_len) {
    if (match_write_byte(src, src_len, i)) {
      i = i + 10;
      parse_int_at(src, src_len, i);
      i = parse_next;
      writes = writes + 1;
    } else {
      i = i + 1;
    }
  }
  return writes;
}

static long emit_source(char *src, long src_len)
{
  long i = 0;
  long writes = 0;
  out_len = 0;
  while (i < src_len) {
    if (match_write_byte(src, src_len, i)) {
      long n;
      i = i + 10;
      n = parse_int_at(src, src_len, i);
      i = parse_next;
      emit_const_write(n);
      writes = writes + 1;
    } else {
      i = i + 1;
    }
  }
  if (writes == 0) die("no write_byte calls found");
  emit_byte(OP_HALT);
  return out_len;
}

static void write_u32_file(FILE *file, long x)
{
  fputc((int)low_byte(x), file);
  fputc((int)low_byte(x / 256), file);
  fputc((int)low_byte(x / 65536), file);
  fputc((int)low_byte(x / 16777216), file);
}

static void write_bytecode(const char *path, char *src, long src_len)
{
  FILE *file = fopen(path, "wb");
  long writes = count_writes(src, src_len);
  long code_len = writes * 14 + 1;
  long actual_len;
  if (writes == 0) die("no write_byte calls found");
  if (!file) die("cannot open output file");
  fputc('M', file);
  fputc('Z', file);
  fputc('B', file);
  fputc('C', file);
  write_u32_file(file, 1);
  write_u32_file(file, code_len);
  write_u32_file(file, 3);
  write_u32_file(file, 0);
  out_file = file;
  actual_len = emit_source(src, src_len);
  if (actual_len != code_len) die("internal bytecode length mismatch");
  fclose(file);
}

int main(int argc, char **argv)
{
  long src_len;
  char *src;
  if (argc != 3) {
    fputs("usage: mlc-seed INPUT.ml OUTPUT.mzbc\n", stderr);
    return 2;
  }
  src = read_file(argv[1], &src_len);
  write_bytecode(argv[2], src, src_len);
  return 0;
}
