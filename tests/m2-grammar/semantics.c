#include <stdio.h>
#include <stdlib.h>

int global_count = 7;
int values[4];
int *global_pointer;

int bump_static(void) {
  static int count = 20;
  return count++;
}

int main(void) {
  int old;
  int *p;
  int side = 0;
  int total = 0;
  static int static_values[3];
  static int static_count;
  char chars[3];
  char *heap;
  values[0] = 11;
  values[1] = 22;
  values[2] = 33;
  values[3] = 44;
  global_pointer = values;

  old = global_count++;
  if (old != 7 || global_count != 8) return 1;
  old = global_count--;
  if (old != 8 || global_count != 7) return 2;
  if (bump_static() != 20) return 3;
  if (bump_static() != 21) return 4;
  p = global_pointer++;
  if (p != values || *global_pointer != 22) return 5;
  p = global_pointer--;
  if (*p != 22 || global_pointer != values) return 6;
  if (*(values + 2) != 33 || *(2 + values) != 33) return 7;
  if ((values + 3) - values != 3) return 8;
  if (values - (values + 3) != -3) return 20;
  if ((chars + 2) - chars != 2) return 21;
  static_values[1] = 81;
  if (*(1 + static_values) != 81) return 22;
  static_count = 0;
  if (++static_count != 1 || static_count-- != 1) return 23;
  if (static_count != 0) return 24;

  /* Precedence, associativity, short-circuiting, and comma lowering. */
  if (2 + 3 * 4 != 14) return 9;
  if (20 - 5 - 3 != 12) return 10;
  if (0 && ++side) return 11;
  if (!(1 || ++side)) return 12;
  old = 0 ? ++side : 9;
  if (old != 9 || side != 0) return 13;
  if ((2 && 4) != 1 || (2 || 4) != 1) return 25;
  if ((0 || 2 && 4) != 1) return 26;
  if ((1 || 0 && ++side) != 1 || side != 0) return 27;
  if (!(0 || ++side) || side != 1) return 28;
  if (!(1 && ++side) || side != 2) return 29;
  old = (side = 3, side + 4);
  if (old != 7) return 14;
  for (int i = 0; i < 4; i++) total += values[i];
  if (total != 110) return 15;
  global_count = 1;
  if (values[global_count++] != 22 || global_count != 2) return 17;
  if (values[global_count--] != 33 || global_count != 1) return 18;
  if (++global_count != 2 || --global_count != 1) return 19;

  /* Exercise the adapter's full-libc selection as well as core-only tests. */
  heap = malloc(4);
  if (!heap) return 16;
  heap[0] = 'O';
  heap[1] = 'K';
  heap[2] = '\n';
  heap[3] = 0;
  fputs(heap, stdout);
  free(heap);
  return 0;
}
