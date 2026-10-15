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

  /* Unevaluated operands check target inference even on i386; these do not
     claim support for its runtime 64-bit arithmetic or loads. */
  if (sizeof(1L) != sizeof(long) || sizeof(1UL) != sizeof(unsigned long)) return 14;
  if (sizeof(1LL) != 8 || sizeof(1ULL) != 8) return 15;
  if (sizeof(2147483648) != 8 || sizeof(4294967296U) != 8) return 16;
  if (sizeof(0xffffffff) != 4 || sizeof(4294967295U) != 4) return 17;
  if (sizeof(0xffffffffL) != sizeof(long) || sizeof(4294967296L) != 8) return 18;
  if (sizeof(+1L) != sizeof(long) || sizeof(1 ? 1L : 1U) != sizeof(long)) return 19;
  if (sizeof(1 ? 1LL : 1UL) != 8 || sizeof(1U << 1LL) != 4) return 20;
  if (sizeof(1 ? 4294967296L : 1L) != 8) return 21;
  if ((-1L < 0xffffffffL) != (sizeof(long) == 8)) return 26;

  /* Execute wide operations only on the three supported 64-bit targets. */
  if (sizeof(long) == 8) {
    int one = 1;
    int choose = 1;
    long expected = 4294967296L;
    long negative = -4294967296L;
    unsigned long positive = +4294967296UL;
    long selected = choose ? 4294967296L : 1L;
    long long longlong = +4294967296LL;
    unsigned long long top = 18446744073709551615ULL;
    one /= 4294967296L;
    if (one != 0) return 22;
    if (negative != -expected || positive != expected) return 23;
    if (selected != expected || longlong != expected) return 24;
    if (top != ~0ULL || !(0xffffffffffffffff > 1ULL)) return 25;
  }
  return 0;
}
