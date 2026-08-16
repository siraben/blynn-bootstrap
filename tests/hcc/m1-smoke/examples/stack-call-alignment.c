extern int hcc_stack_is_aligned(void);

static int one_slot(void) {
  long values[1];
  values[0] = 1;
  return values[0] == 1 && hcc_stack_is_aligned();
}

static int two_slots(void) {
  long values[2];
  values[0] = 1;
  values[1] = 2;
  return values[0] + values[1] == 3 && hcc_stack_is_aligned();
}

int main(void) {
  return hcc_stack_is_aligned() && one_slot() && two_slots() ? 0 : 1;
}
