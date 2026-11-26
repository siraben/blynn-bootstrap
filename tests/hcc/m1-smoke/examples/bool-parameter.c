static int check(_Bool value, int other) {
  _Bool *address = &value;
  return value == 1 && *address == 1 && other == 42;
}

int main(void) {
  return !check(256, 42);
}
