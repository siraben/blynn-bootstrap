struct Pair { long a; long b; };
int sum_down(int n) {
  struct Pair p = {0};
  p.a = n;
  if (n == 0) return p.a;
  return sum_down(n - 1) + p.a;
}
int main(){return sum_down(2);}
