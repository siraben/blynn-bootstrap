struct A { char a[3]; };
struct B { char x; struct A a; char z; };
union U { char a[5]; struct A b; };
struct C { char x; union U u; char z; };
struct Shorts { short a[3]; };
struct D { char x; struct Shorts s; char z; };
struct P { void *p; char c; };
struct Q { char x; struct P p; char z; };
struct B global = {1, {{2, 3, 4}}, 5};
int main(void) {
  struct B b[2] = {{1, {{2, 3, 4}}, 5}, {6, {{7, 8, 9}}, 10}};
  struct D d;
  if (sizeof(struct B) != 5 || sizeof(struct C) != 7) return 1;
  if (sizeof(struct D) != 10) return 2;
  if ((char *)&b[0].a - (char *)&b[0] != 1) return 3;
  if ((char *)&d.s - (char *)&d != 2) return 4;
  if (b[1].a.a[2] != 9 || global.z != 5) return 5;
  if (sizeof(struct Q) != 4 * sizeof(void *)) return 6;
  return 0;
}
