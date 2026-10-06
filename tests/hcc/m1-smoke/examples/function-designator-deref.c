struct hooks {
  int (*run)(int);
};

static int increment(int value) {
  return value + 1;
}

static const struct hooks host_hooks = { increment };
static int (*callback)(int) = increment;
static int (**callback_slot)(int) = &callback;

int main(void) {
  if ((*host_hooks.run)(40) != 41) return 1;
  if ((*callback)(41) != 42) return 2;
  if ((**callback)(42) != 43) return 3;
  if ((*callback_slot)(43) != 44) return 4;
  return 0;
}
