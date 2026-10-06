struct va_state {
  unsigned int gp_offset;
  unsigned int fp_offset;
  void *overflow_arg_area;
  void *reg_save_area;
};

typedef struct va_state va_list[1];

#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_end(ap) __builtin_va_end(ap)
#define va_arg(ap, type) __builtin_va_arg(ap, type)

static long next_long(va_list ap) {
  return va_arg(ap, long);
}

static long sum_forwarded(int marker, ...) {
  va_list ap;
  long total;

  va_start(ap, marker);
  total = next_long(ap);
  total = total + next_long(ap);
  total = total + next_long(ap);
  total = total + next_long(ap);
  total = total + next_long(ap);
  total = total + next_long(ap);
  total = total + next_long(ap);
  va_end(ap);
  return total;
}

int main(void) {
  return sum_forwarded(0, 1L, 2L, 4L, 8L, 16L, 32L, 64L) == 127
    ? 0 : 1;
}
