int main(void) {
  int a = -1;
  unsigned b = 2, all = 4294967295U;
  long wide = -1;
  if (a / b != 2147483647) return 1;
  if (!(a == all) || !(all == a)) return 2;
  if (a < b || b > a) return 3;
  /* On LP64 the unsigned operand must widen without sign extension;
     on ILP32 both operands convert to unsigned long. */
  if (sizeof(long) > sizeof(int)) {
    if (!(wide < all) || !(all > wide)) return 4;
  } else {
    if (!(wide == all)) return 5;
  }
  return 0;
}
