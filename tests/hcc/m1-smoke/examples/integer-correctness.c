/* Static data uses byte checks so i386 need not execute wide loads. */
enum { wide_enum = 0xffffffffffffffffULL, model = -1L < 1U };
_Static_assert(4294967296ULL, "wide constant truth");
unsigned long extended = ~0U;
unsigned long long quotient = wide_enum / 3ULL;
int signed_quotient = -5 / 2, remainder = -5 % 2;
int comma_size = sizeof((0, (char)0));
int cast_size = sizeof((int)3.0), size_size = sizeof(sizeof(char));
double zeros[1] = {0};

int main(void) {
  int i, negative = -1, dividend = -4, shift = -4, choose = 1;
  unsigned divisor = 2, one = 1, zero = 0;
  unsigned long top = 1;
  unsigned char narrow = 255;
  unsigned char *bytes = (unsigned char *)&extended;
  void *pointer = &i;
  int is_null;
  for (i = 0; i < sizeof(extended); ++i)
    if (bytes[i] != (i < 4 ? 255 : 0)) return 1;
  bytes = (unsigned char *)&quotient;
  for (i = 0; i < 8; ++i) if (bytes[i] != 85) return 2;
  bytes = (unsigned char *)zeros;
  for (i = 0; i < sizeof(zeros); ++i) if (bytes[i]) return 3;
  if (signed_quotient != -2 || remainder != -1 || model != (sizeof(long) == 8)) return 4;
  if (comma_size != 1 || cast_size != sizeof(int) || size_size != sizeof(void *)) return 5;

  if (negative / divisor != 2147483647 || !(negative == 4294967295U)) return 6;
  dividend /= divisor;
  shift >>= one;
  top <<= sizeof(long) * 8 - 1;
  top >>= 1;
  if (dividend != 2147483646 || shift != -2 || top != (1UL << (sizeof(long) * 8 - 2))) return 7;
  if ((~zero >> 31) != 1 || (-one >> 31) != 1) return 8;
  if ((choose ? negative : one) / 2 != 2147483647) return 9;
  if (++narrow != 0 || narrow != 0) return 10;

  if (sizeof(long) == 8) {
    int value = 1;
    long wide = 4294967296L;
    value /= 4294967296L;
    if (value || -4294967296L != -wide || +4294967296UL != wide) return 11;
    if ((choose ? 4294967296L : 1L) != wide) return 12;
    pointer = (void *)4294967296UL;
  }
  if (sizeof(4294967296L) != 8 || sizeof(+1L) != sizeof(long)) return 13;
  /* Both value and branch lowering must preserve a pointer's high bits. */
  is_null = 0U == pointer;
  if (is_null || 0U == pointer) return 14;
  return 0;
}
