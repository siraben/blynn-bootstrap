/* Reduced from bzip2 1.0.8 decompress.c: GET_BITS places resume labels
   inside BZ2_decompress's state switch, including inside a loop. */
static int resume(int state) {
  int value = 0;
  switch (state) {
  case 0:
    value = 10;
    /* fall through into the loop normally, or dispatch straight to case 1 */
    for (; value < 12; ++value) {
    case 1:
      value += 2;
      if (state == 1) break;
    }
    switch (value) {
    case 2:
      return 20;
    default:
      return value;
    }
  case 3:
    if (0)
    case 4:
    case 5:
      return 40;
    return 30;
  default:
    return 50;
  }
}

int main(void) {
  return resume(0) != 13 || resume(1) != 20 || resume(2) != 50 ||
         resume(3) != 30 || resume(4) != 40 || resume(5) != 40;
}
