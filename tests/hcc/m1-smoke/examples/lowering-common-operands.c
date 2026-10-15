static int pointer_null_checks(void *p) {
  int eq_left = 0U == p, eq_right = p == 0U;
  int ne_left = 0U != p, ne_right = p != 0U;
  int choose = 0;
  void *q = choose ? 0U : p;
  if (eq_left || eq_right || !ne_left || !ne_right) return 6;
  if (0U == p) return 7;
  if (p == 0U) return 8;
  if (0U != p) { } else return 9;
  if (p != 0U) { } else return 10;
  if ((1U - 1U) == p || p == 0UL) return 11;
  /* Already-correct conditional pointer/null conversion is a control. */
  if (q == 0) return 12;
  q = choose ? p : 0U;
  if (q != 0U || 0U != q || !(q == 0U) || !(0U == q)) return 13;
  /* Exact review discriminator, including the value comparison path. */
  return (0U == p) || !(0U != p) || (p == 0);
}

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
  /* No wide arithmetic on i386; use an ordinary non-null pointer there. */
  if (sizeof(void *) == 8)
    return pointer_null_checks((void *)4294967296UL);
  return pointer_null_checks(&a);
}
