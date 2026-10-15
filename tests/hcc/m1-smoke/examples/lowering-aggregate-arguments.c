struct A { int n; char bytes[3]; };
union U { int n; char bytes[4]; };
int change(struct A a) { a.n = 9; a.bytes[1] = 8; return a.n + a.bytes[1]; }
int separate(struct A a, struct A b) { a.n = 20; return b.n; }
int nested(struct A a, int depth) {
  if (!depth) { a.n = 30; return a.n; }
  nested(a, depth - 1);
  return a.n;
}
int change_union(union U u) { u.n = 40; return u.n; }
int decay(int a[1]) { a[0] = 50; return a[0]; }
int main(void) {
  struct A a = {1, {2, 3, 4}};
  union U u = {5};
  int data[1] = {6};
  int (*fn)(struct A) = change;
  if (change(a) != 17 || a.n != 1 || a.bytes[1] != 3) return 1;
  if (fn(a) != 17 || a.n != 1) return 2;
  if (separate(a, a) != 1) return 3;
  if (nested(a, 2) != 1 || a.n != 1) return 4;
  if (change_union(u) != 40 || u.n != 5) return 5;
  decay(data);
  if (data[0] != 50) return 6;
  return 0;
}
