typedef int unary_function(int);

static unary_function add_one;

static int add_one(int value) {
  return value + 1;
}

extern __inline__ __attribute__((__gnu_inline__)) int double_value(int value) {
  return value * 2;
}

int double_value(int value) {
  return value + value;
}

int main(void) {
  return add_one(41) == 42 && double_value(21) == 42 ? 0 : 1;
}
