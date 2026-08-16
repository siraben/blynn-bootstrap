int main(void) {
  unsigned long value = 1UL << 63;
  value >>= 1;
  return value == (1UL << 62) ? 0 : 61;
}
