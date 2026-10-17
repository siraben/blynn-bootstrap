#define F(x) ((x)+1)
#define G(x) F(x)
#define RET() F
#define A B
#define B A
int A = 7;
int self(int x) { return x; }
#define self(x) self(x)
int g = 3;
#define f(a) a*g
#define g(a) f(a)

#define HEADER <pp header.h>
#if F(1) == 2
#include HEADER
#elif 1/0
#error ineligible elif
#endif
int included = HEADER_VALUE;
#undef HEADER_VALUE
#undef HEADER
#define HEADER <ppheader.h>
#include HEADER
int adjacent = HEADER_VALUE;
#if 0
#if bad tokens (
#error inactive conditional
#endif
#endif
#if -5/2 != -2 || -5%2 != -1 || -1L < 1U || ~0U != 18446744073709551615ULL
#error preprocessing integer model
#endif
#if ((1ULL << 63) >> 63) != 1
#error full-width preprocessing shift
#endif

#define S(x) #x
#define EXPAND(x) S(x)
#define LEAD(x) x b
#define TRAIL(x) a x
#define PASTE(x) a x##x
int same(char *a, char *b) {
  while (*a && *a == *b) { ++a; ++b; }
  return *a == *b;
}
int main(void) {
  if (G(F(1)) != 3 || RET()(1) != 2 || A != 7 || self(5) != 5) return 1;
  if (f(2)(9) != 54 || included != 7 || adjacent != 9) return 2;
  if (!same(S(a+b), "a+b") || !same(S(a + b), "a + b")) return 3;
  if (!same(EXPAND(a+LEAD()), "a+ b")) return 4;
  if (!same(EXPAND(TRAIL()b), "a b")) return 5;
  return !same(EXPAND(PASTE()b), "a b");
}
