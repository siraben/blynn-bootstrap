int main(void) {
  unsigned x = 0, one = 1;
  unsigned char small = 0;
  if ((~x >> 31) != 1) return 1;
  if ((-one >> 31) != 1) return 2;
  if ((~0U >> 31) != 1) return 3;
  if (~small != -1 || sizeof(+small) != sizeof(int)) return 4;
  return 0;
}
