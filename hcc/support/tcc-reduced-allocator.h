/* Reduced TinyCC libc only: unsigned sizes, unaligned bump allocation, no-op free.
 * Keep the existing brk failure behavior; this is not a general host allocator. */
static char *hcc_reduced_brk;
static char *hcc_reduced_malloc;

void *malloc(unsigned size) {
  char *out;
  if (!hcc_reduced_brk) {
    hcc_reduced_brk = (char *)brk(0);
    hcc_reduced_malloc = hcc_reduced_brk;
  }
  if (hcc_reduced_brk < hcc_reduced_malloc + size) {
    hcc_reduced_brk = (char *)brk(hcc_reduced_malloc + size);
    if ((long)hcc_reduced_brk < 0) return 0;
  }
  out = hcc_reduced_malloc;
  hcc_reduced_malloc = hcc_reduced_malloc + size;
  return out;
}

void *calloc(unsigned count, unsigned size) {
  void *out = malloc(count * size);
  if (out) memset(out, 0, count * size);
  return out;
}

void free(void *ptr) {}

void exit(int code) {
  _exit(code);
}
