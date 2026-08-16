static int shared = 2;

static int helper(void) {
  return shared;
}

int right_value(void) {
  return helper();
}
