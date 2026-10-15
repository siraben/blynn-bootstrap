int main(void) {
  int c = 1, a = -1, hits = 0;
  unsigned b = 1;
  unsigned char small = 2;
  int data[1] = {7};
  if ((c ? -1 : 1U) < 0) return 1;
  if ((c ? a : b) / 2 != 2147483647) return 2;
  c = 0;
  if ((c ? b : a) / 2 != 2147483647) return 3;
  if ((c ? ++hits : small) != 2 || hits != 0) return 4;
  if (sizeof(c ? small : small) != sizeof(int)) return 5;
  if (*(c ? 0 : data) != 7) return 6;
  return 0;
}
