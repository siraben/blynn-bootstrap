unsigned long wide_constant(void) { return 0x123456789abcdefUL; }

int main() {
  unsigned short us = 65535;
  signed short ss = -1;
  unsigned long ul = 7;
  long long sll = -2;
  unsigned long long ull = 9;
  _Bool yes = 3;

  if (sizeof(short) != 2) return 1;
  if (sizeof(unsigned short) != 2) return 2;
  if (sizeof(long long) != 8) return 3;
  if (sizeof(unsigned long long) != 8) return 4;
  if (sizeof(_Bool) != 1) return 5;
  if (sizeof(long double) < sizeof(double)) return 12;
  if (sizeof(long double) != 16) return 13;
  if (us != 65535) return 6;
  if (ss != -1) return 7;
  if (ul != 7) return 8;
  if (sll != -2) return 9;
  if (ull != 9) return 10;
  if (yes != 1) return 11;
  if ((wide_constant() & 0xffff) != 0xcdef) return 14;
  if (sizeof(long) == 8 && ((wide_constant() >> 16) >> 16) != 0x1234567) return 15;
  if ((long)(int)wide_constant() != -1985229329L) return 16;
  if ((unsigned long)(unsigned int)wide_constant() != 0x89abcdefUL) return 17;
  return 0;
}
