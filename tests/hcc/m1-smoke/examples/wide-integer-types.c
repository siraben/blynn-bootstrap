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
  if (us != 65535) return 6;
  if (ss != -1) return 7;
  if (ul != 7) return 8;
  if (sll != -2) return 9;
  if (ull != 9) return 10;
  if (yes != 1) return 11;
  return 0;
}
