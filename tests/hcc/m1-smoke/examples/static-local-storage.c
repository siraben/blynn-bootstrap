int shared_value = 7;

static int cached_increment(int value) {
  static int initialized;
  static int increment = 1;
  if (!initialized) {
    initialized = 1;
    return cached_increment(value);
  }
  return value + increment;
}

static int independent_counter(void) {
  static int value = 40;
  value = value + 1;
  return value;
}

static int read_external(void) {
  extern int shared_value;
  return shared_value;
}

int main(void) {
  return cached_increment(41) == 42
    && cached_increment(9) == 10
    && independent_counter() == 41
    && independent_counter() == 42
    && read_external() == 7 ? 0 : 1;
}
