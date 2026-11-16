int load(int *p) { return *p; }

int main() {
  int x = -1;
  if ((char)128 != -128) return 1;
  if ((char)255 != -1) return 2;
  if ((unsigned char)-1 != 255) return 3;
  if (load(&x) != -1) return 4;
  if ('\377' != -1) return 5;
  if ('\xe9' != (char)0xe9) return 6;
  if ('\x7f' != 127) return 7;
#if '\377' >= 0
  return 8;
#endif
  return 0;
}
