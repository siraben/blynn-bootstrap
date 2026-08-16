struct packed_bits {
  unsigned first : 1;
  unsigned second : 2;
  unsigned third : 5;
  int signed_value : 3;
};

struct split_bits {
  unsigned first : 1;
  unsigned : 0;
  unsigned second : 1;
  unsigned char tail;
};

struct embedded_tail {
  void *extra_arg;
  unsigned use_extra_arg : 1;
  unsigned maybe_empty_object : 1;
  unsigned alloc_failed : 1;
};

struct containing_tail {
  struct embedded_tail embedded;
  void *next;
};

union bit_union {
  unsigned value : 3;
  unsigned full;
};

union zero_width_union {
  unsigned : 0;
  unsigned value : 1;
};

static struct packed_bits global_bits = { 1, 2, 19, -3 };
static union bit_union global_union = { 5 };
static union zero_width_union global_zero_width_union = { 1 };

static unsigned one(void) {
  return 1;
}

int main(void) {
  struct packed_bits bits;
  struct packed_bits initialized = { one(), 1, 23, -3 };
  struct split_bits split;
  struct containing_tail containing;

  if (sizeof(struct packed_bits) != sizeof(unsigned)) return 1;
  if (sizeof(struct split_bits) != 2 * sizeof(unsigned)) return 2;
  if (sizeof(struct embedded_tail) != 2 * sizeof(void *)) return 3;
  if ((char *)&containing.next - (char *)&containing !=
      2 * sizeof(void *)) return 4;
  if (global_bits.first != 1) return 5;
  if (global_bits.second != 2) return 13;
  if (global_bits.third != 19) return 14;
  if (global_bits.signed_value != -3) return 15;
  if (global_union.value != 5) return 6;
  if (initialized.first != 1 || initialized.second != 1 ||
      initialized.third != 23 || initialized.signed_value != -3) return 7;

  bits.first = 1;
  bits.second = 3;
  bits.third = 17;
  bits.signed_value = -2;
  if (bits.first != 1 || bits.second != 3 || bits.third != 17) return 8;
  if (bits.signed_value != -2) return 9;
  bits.second += 1;
  if (bits.second != 0 || bits.first != 1 || bits.third != 17) return 10;
  if (sizeof(union zero_width_union) != sizeof(unsigned) ||
      global_zero_width_union.value != 1) return 11;

  split.first = 1;
  split.second = 1;
  split.tail = 42;
  if (split.first != 1 || split.second != 1 || split.tail != 42) return 12;
  return 0;
}
