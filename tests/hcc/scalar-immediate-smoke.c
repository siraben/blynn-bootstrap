int is_space(int ch) {
  return ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r';
}

int main(void) {
  if (!is_space(' ')) return 1;
  if (!is_space('\n')) return 2;
  if (is_space('x')) return 3;
  return 0;
}
