int load(int *p) { return *p; }

int main() {
  int x = -1;
  if ((char)128 != -128) return 1;
  if ((char)255 != -1) return 2;
  if ((unsigned char)-1 != 255) return 3;
  if (load(&x) != -1) return 4;
  return 0;
}
