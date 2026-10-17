typedef char T;
enum { E = 3, negative = -3, minimum = -2147483647 - 1 };
int stored = negative;
int parameter(int T) { return sizeof(T) == sizeof(int) ? T : 0; }
int array(int T[static const (int)1.0]) {
  return sizeof(T) == sizeof(int *) ? T[0] : 0;
}
int main(void) {
  int x = 7;
  /* A block prototype must accept array modifiers without leaking names. */
  int array(int T[const static 1]);
  if (parameter(7) != 7 || array(&x) != 7 || sizeof(T) != 1) return 1;
  {
    /* Binding starts before the initializer and masks both ordinary names. */
    int T = sizeof(T), E = 9;
    if (T != sizeof(int) || E != 9) return 2;
  }
  if (sizeof(T) != 1 || E != 3) return 3;
  for (int T = 0; T < 1; ++T) x += T;
  if (sizeof(T) != 1) return 4;
  if (negative != -3 || stored != -3 || minimum != -2147483647 - 1) return 5;
  return sizeof(minimum) != sizeof(int);
}
