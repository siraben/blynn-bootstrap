static int shared = 1;

static int helper(void) {
  return shared;
}

int left_value(void) {
  return helper();
}
