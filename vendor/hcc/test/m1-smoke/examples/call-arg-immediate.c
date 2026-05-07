int pick(long a, long b, long c, long d, long e) {
  if (a != 1) return 1;
  if (b != 2) return 2;
  if (c != 3) return 3;
  if (d != 4) return 4;
  if (e != 4294967295u) return 5;
  return 42;
}
int main(){return pick(1, 2, 3, 4, 4294967295u);}
