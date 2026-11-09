typedef unsigned long size_t;

void *memset(void *ptr, int value, size_t count);

long brk(void *addr);
void _exit(int code);

void __assert_fail(char *expr, char *file, unsigned line, char *function) {
  _exit(1);
}

#include "tcc-reduced-allocator.h"
