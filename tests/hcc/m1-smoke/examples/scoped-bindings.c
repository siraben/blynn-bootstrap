struct Record {
  int value;
};

static unsigned char convert(int value) {
  return value + 2;
}

static int other(int value) {
  return value + 5;
}

int main(void) {
  struct Record outer = {42};
  int (*convert)(int) = other;
  {
    struct Record;
    struct Record *ptr;
    struct Record {
      char value;
    } inner = {7};
    ptr = &inner;
    extern unsigned char convert(int);
    if (sizeof(outer) != sizeof(int) || sizeof(*ptr) != 1) return 1;
    if (outer.value != 42 || ptr->value != 7) return 2;
    if (sizeof(convert(0)) != 1 || convert(1) != 3) return 3;
  }
  if (sizeof(outer) != sizeof(int) || convert(1) != 6) return 4;
  return 0;
}
