struct Pair {
  int tag;
  long value;
};

char *first_text() { return "first"; }
char *second_text() { return "second"; }

int choose(int *calls, int value) {
  *calls = *calls + 1;
  return value;
}

int main() {
  struct Pair a = { 69, 1234 };
  struct Pair b = { 70, 5678 };
  struct Pair out;
  struct Pair *pa = &a;
  struct Pair *pb = &b;
  int calls = 0;

  out = *((1 ? pa : pb));
  if (out.tag != 69) return 1;
  if (out.value != 1234) return 2;

  out = *((choose(&calls, 0) ? pb :
           (choose(&calls, 1) ? (choose(&calls, 0) ? pb : pa) : pb)));
  if (out.tag != 69 || out.value != 1234) return 3;
  if (calls != 3) return 4;
  out = *((choose(&calls, 1) ? (choose(&calls, 1) ? pb : pa) : pa));
  if (out.tag != 70 || out.value != 5678) return 5;
  if (calls != 5) return 6;
  if (first_text()[0] != 'f' || second_text()[0] != 's') return 7;
  return 0;
}
