typedef int outer_t;

enum { TOP_A = 5 };

int main() {
  outer_t outer = TOP_A;
  {
    typedef char outer_t;
    enum { TOP_A = 9, INNER_B = TOP_A + 3 };
    outer_t inner = -1;
    if (sizeof(outer_t) != 1) return 1;
    if (inner != -1) return 2;
    if (TOP_A != 9) return 3;
    if (INNER_B != 12) return 4;
  }
  if (sizeof(outer_t) != 4) return 5;
  if (outer != 5) return 6;
  if (TOP_A != 5) return 7;
  return 0;
}
