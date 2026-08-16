static const int literal_size = sizeof("COLLECT_GCC=");

int main(void) {
  return literal_size == 13
    && sizeof("") == 1
    && __alignof__("array") == __alignof__(char) ? 0 : 1;
}
