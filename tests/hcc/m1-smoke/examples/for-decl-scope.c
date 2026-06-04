int main() {
  int total = 0;
  int i = 100;
  for (int i = 0; i < 4; i = i + 1) {
    total = total + i;
  }
  if (total != 6) return 1;
  if (i != 100) return 2;
  return 0;
}
