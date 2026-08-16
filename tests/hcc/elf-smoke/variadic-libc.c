struct hcc_va_state {
  unsigned int gp_offset;
  unsigned int fp_offset;
  void *overflow_arg_area;
  void *reg_save_area;
};
typedef struct hcc_va_state va_list[1];

#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_end(ap) __builtin_va_end(ap)

int vsnprintf(char *, unsigned long, const char *, va_list);
int abs(int);

static int increment(int value) {
  return value + 1;
}

static int apply(int (*callback)(int), int value) {
  return callback(value);
}

static int next_count(void) {
  static int count;
  return ++count;
}

static int render(char *out, const char *format, ...) {
  va_list ap;
  int result;
  va_start(ap, format);
  result = vsnprintf(out, 64, format, ap);
  va_end(ap);
  return result;
}

int main(void) {
  char out[64];
  int result = render(out, "%s:%d:%d:%d:%d:%d:%d:%d",
                      "ok", 1, 2, 3, 4, 5, 6, 7);
  return result == 16
    && apply(increment, 41) == 42
    && apply(abs, -42) == 42
    && next_count() == 1 && next_count() == 2
    && out[0] == 'o' && out[1] == 'k' && out[2] == ':'
    && out[3] == '1' && out[15] == '7' && out[16] == 0 ? 0 : 1;
}
