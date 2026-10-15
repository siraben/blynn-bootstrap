struct Counter { unsigned char n; };
int main(void) {
  unsigned char x = 255, y = 0;
  unsigned short s = 65535;
  struct Counter c = {255};
  int array[2] = {7, 9};
  int *p = array;
  if (++x != 0 || x != 0) return 1;
  if (--y != 255 || y != 255) return 2;
  if (++s != 0 || s != 0) return 3;
  if (++c.n != 0 || c.n != 0) return 4;
  if (*++p != 9) return 5;
  /* Control: postfix already stores and subsequently reads a narrow value. */
  x = 255;
  if (x++ != 255 || x != 0) return 6;
  return 0;
}
