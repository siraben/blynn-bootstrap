#define VALUE 42
#define ENABLE_SUM 1

int main(int argc, char **argv) {
  const char *msg = "hello\n";
#if ENABLE_SUM
  int sum = 1+2 + 0xffUL;
#else
  int sum = 0;
#endif
  /* block comment */
  if (argc >= 2 && argv[1] != 0) {
    return VALUE + msg[0] + sum;
  }
  return 'x';
}
