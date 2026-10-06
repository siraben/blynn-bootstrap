#include <stdlib.h>
#include <zlib.h>

void *hcc_builtin_alloca(unsigned long size) {
  return malloc(size ? size : 1);
}

int hcc_builtin_clzl(unsigned long value) {
  int count = 0;
  if (!value) return 64;
  while ((value & (1UL << 63)) == 0) {
    value <<= 1;
    count++;
  }
  return count;
}

int hcc_builtin_ctzl(unsigned long value) {
  int count = 0;
  if (!value) return 64;
  while ((value & 1UL) == 0) {
    value >>= 1;
    count++;
  }
  return count;
}

int hcc_builtin_ffsl(long value) {
  return value ? hcc_builtin_ctzl((unsigned long)value) + 1 : 0;
}

int hcc_builtin_popcountl(unsigned long value) {
  int count = 0;
  while (value) {
    count += (int)(value & 1UL);
    value >>= 1;
  }
  return count;
}

int hcc_deflate_init(z_stream *stream, int level) {
  return deflateInit(stream, level);
}

int hcc_inflate_init(z_stream *stream) {
  return inflateInit(stream);
}
