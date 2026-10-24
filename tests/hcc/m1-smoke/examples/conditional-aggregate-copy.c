struct Pair {
  int tag;
  long value;
};

int main() {
  struct Pair a = { 69, 1234 };
  struct Pair b = { 70, 5678 };
  struct Pair out;
  struct Pair *pa = &a;
  struct Pair *pb = &b;

  out = *((1 ? pa : pb));
  if (out.tag != 69) return 1;
  if (out.value != 1234) return 2;
  return 0;
}
