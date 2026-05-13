typedef int Compare(void *ctx, int a, int b);

typedef struct Box {
  int value;
} Box;

int less_than(void *ctx, int a, int b) {
  return a + *(int *)ctx < b;
}

int apply(Compare *cmp, void *ctx, int a, int b) {
  if (cmp(ctx, a, b) != 1) return 1;
  return 0;
}

int read_box(Box *box, struct Box *same) {
  return box->value + same->value;
}

int pointer_element_size(void) {
  static const char * const libs[] = { "a", "b", 0 };
  return sizeof(*libs) == sizeof(char *);
}

int main() {
  int bias = 2;
  Box box;
  box.value = 5;
  if (apply(less_than, &bias, 3, 6) != 0) return 1;
  if (read_box(&box, &box) != 10) return 2;
  if (!pointer_element_size()) return 3;
  if (__func__[0] != 'm') return 4;
  return 0;
}
