static int unsigned_case(unsigned int x) {
  switch (x) {
  case -1:
    return 1;
  default:
    return 0;
  }
}

static int narrow_case(unsigned char x) {
  switch (x) {
  case -1:
    return 1;
  case 255:
    return 2;
  default:
    return 0;
  }
}

int main(void) {
  if (!unsigned_case((unsigned int)-1) || unsigned_case(0)) return 1;
  if (narrow_case(255) != 2) return 2;
  switch (__LINE__) {
  case __LINE__: return 0;
  default: return 3;
  }
}
