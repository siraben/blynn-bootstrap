#define VALUE 42

int main(int argc, char **argv) {
  const char *msg = "hello\n";
  int sum = 1+2 + 0xffUL;
  /* block comment */
  if (argc >= 2 && argv[1] != 0) {
    return VALUE + msg[0] + sum;
  }
  return 'x';
}
