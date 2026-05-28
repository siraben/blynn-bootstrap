int main(void) {
  int i = 0;
  int sum = 0;

  for (i = 0; i < 6; i++) {
    if (i == 3) continue;
    sum += i;
  }
  if (sum != 12) return 1;

  i = 0;
  sum = 0;
  while (i < 6) {
    i++;
    if (i == 3) continue;
    sum += i;
  }
  if (sum != 18) return 2;

  i = 0;
  sum = 0;
  do {
    i++;
    if (i == 3) continue;
    sum += i;
  } while (i < 6);
  if (sum != 18) return 3;

  return 42;
}
