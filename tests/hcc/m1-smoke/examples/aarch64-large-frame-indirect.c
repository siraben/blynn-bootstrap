static long identity(long value) {
  return value;
}

static long invoke(long (*callee)(long)) {
  char buffer[32768];
  buffer[0] = 41;
  long argument = buffer[0] + 1;
  return callee(argument);
}

int main(void) {
  return invoke(identity) != 42;
}
