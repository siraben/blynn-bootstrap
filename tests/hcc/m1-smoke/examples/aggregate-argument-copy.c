struct Pair {
  long first;
  long second;
};

static long mutate_copy(struct Pair value) {
  value.first = 99;
  return value.first + value.second;
}

static long call_indirect(long (*fn)(struct Pair), struct Pair value) {
  return fn(value);
}

static void mutate_array(long *values) {
  values[0] = 7;
}

int main(void) {
  struct Pair value = { 1, 2 };
  long values[2] = { 3, 4 };

  if (mutate_copy(value) != 101)
    return 1;
  if (value.first != 1)
    return 2;
  if (call_indirect(mutate_copy, value) != 101)
    return 3;
  if (value.first != 1)
    return 4;
  mutate_array(values);
  if (values[0] != 7 || values[1] != 4)
    return 5;
  return 0;
}
