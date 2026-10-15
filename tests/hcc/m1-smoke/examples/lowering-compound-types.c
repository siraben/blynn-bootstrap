int main(void) {
  int a = -4, rem = -3, signed_shift = -4;
  unsigned b = 2, count = 1;
  unsigned long top = 1, one = 1;
  unsigned char small = 128;
  a /= b;
  rem %= b;
  if (a != 2147483646 || rem != 1) return 1;
  top <<= sizeof(long) * 8 - 1;
  top >>= 1;
  if (top != (one << (sizeof(long) * 8 - 2))) return 2;
  signed_shift >>= count;
  if (signed_shift != -2) return 3;
  small >>= count;
  if (small != 64) return 4;
  return 0;
}
