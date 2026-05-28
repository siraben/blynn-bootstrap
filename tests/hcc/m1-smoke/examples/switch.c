int pick(int x) {
  int out = 0;

  switch (x) {
  case 0:
    out = 10;
    break;
  case 1:
    out = 20;
  case 2:
    out += 3;
    break;
  default:
    out = 7;
    break;
  }

  return out;
}

int main(void) {
  if (pick(0) != 10) return 1;
  if (pick(1) != 23) return 2;
  if (pick(2) != 3) return 3;
  if (pick(9) != 7) return 4;
  return 42;
}
