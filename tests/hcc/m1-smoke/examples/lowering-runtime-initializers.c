int global = 11;
int array[2] = {13, 17};
int answer(void) { return 19; }
struct Values { int n; int *p; char text[8]; int *a; int (*f)(void); };
int main(void) {
  int x = 7;
  int a[2] = {x, global};
  int braced[2] = {{3 + 4}, {x}};
  int local[2] = {23, 29};
  struct Values v = {x, &x, "ok", local, answer};
  struct Values constants = {3, &global, "hi", array, answer};
  int *pointers[3] = {&x, local, array + 1};
  if (a[0] != 7 || a[1] != 11) return 1;
  if (v.n != 7 || *v.p != 7 || v.a[1] != 29 || v.f() != 19) return 2;
  if (v.text[0] != 'o' || v.text[7] != 0) return 3;
  if (*constants.p != 11 || constants.a[1] != 17 || constants.f() != 19) return 4;
  if (constants.text[0] != 'h' || constants.text[7] != 0) return 5;
  if (*pointers[0] != 7 || *pointers[1] != 23 || *pointers[2] != 17) return 6;
  if (braced[0] != 7 || braced[1] != 7) return 7;
  return 0;
}
