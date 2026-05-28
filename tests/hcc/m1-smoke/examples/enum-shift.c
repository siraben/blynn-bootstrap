enum {
  FLAG = 1 << 5,
  HALF = FLAG >> 4,
  COMBINED = FLAG + HALF + (16 / 2)
};

int main(void) {
  return COMBINED;
}
