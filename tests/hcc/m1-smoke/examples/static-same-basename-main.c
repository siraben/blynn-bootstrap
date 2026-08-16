int left_value(void);
int right_value(void);

int main(void) {
  return left_value() != 1 || right_value() != 2;
}
