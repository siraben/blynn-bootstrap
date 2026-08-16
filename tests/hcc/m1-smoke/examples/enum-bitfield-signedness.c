enum nonnegative_direction {
  DIR_NONE = 0,
  DIR_FORWARD = 1,
  DIR_REVERSE = 2
};

enum signed_direction {
  DIR_BACKWARD = -1,
  DIR_STILL = 0
};

struct directions {
  enum nonnegative_direction nonnegative : 2;
  enum signed_direction signed_value : 2;
};

int main(void) {
  struct directions value;

  value.nonnegative = DIR_REVERSE;
  value.signed_value = DIR_BACKWARD;

  if (value.nonnegative != 2)
    return 1;
  if (value.signed_value != -1)
    return 2;
  return 0;
}
