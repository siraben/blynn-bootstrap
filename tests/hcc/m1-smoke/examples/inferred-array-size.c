struct pair {
  int left;
  int right;
};

static const struct pair global_pairs[] = {
  {1, 2},
  {3, 4},
  {5, 6}
};

int main(void) {
  int local_values[] = {7, 8, 9, 10};
  return sizeof global_pairs == 3 * sizeof global_pairs[0]
    && global_pairs[2].right == 6
    && sizeof local_values == 4 * sizeof local_values[0]
    && local_values[3] == 10 ? 0 : 1;
}
