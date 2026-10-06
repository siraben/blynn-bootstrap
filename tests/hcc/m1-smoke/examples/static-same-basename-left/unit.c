static int shared = 1;

static int helper(void) {
  return __func__[0] == 'h' ? shared : 0;
}

int left_value(void) {
  return helper();
}
