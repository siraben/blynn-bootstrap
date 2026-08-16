static int select_value(int value) {
  if (value)
    goto before_first_case;

  switch (value) {
  before_first_case:
    return 42;
  case 0:
    return 7;
  default:
    return 9;
  }
}

static int nested_case(int value) {
  switch (value) {
  default:
    if (value) {
    case 'r':
      return 3;
    }
    return 4;
  }
}

int main(void) {
  if (select_value(1) != 42 || select_value(0) != 7) return 1;
  if (nested_case('r') != 3) return 2;
  if (nested_case(1) != 3) return 3;
  if (nested_case(0) != 4) return 4;
  return 0;
}
