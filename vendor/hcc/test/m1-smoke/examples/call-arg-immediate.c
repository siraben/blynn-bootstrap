int pick(long a, long b, long c, long d, long e) {
  if (a != 1) return 1;
  if (b != 2) return 2;
  if (c != 3) return 3;
  if (d != 4) return 4;
  if (e != 4294967295u) return 5;
  return 0;
}
int pick7(long a, long b, long c, long d, long e, long f, long g) {
  if (a != 1) return 10;
  if (b != 2) return 11;
  if (c != 3) return 12;
  if (d != 4) return 13;
  if (e != 4294967295u) return 14;
  if (f != 6) return 15;
  if (g != 7) return 16;
  return 0;
}
int main(){
  if (pick(1, 2, 3, 4, 4294967295u)) return 1;
  if (pick7(1, 2, 3, 4, 4294967295u, 6, 7)) return 2;
  return 42;
}
