#define VALUE 42

int main(int argc, char **argv) {
  const char *msg = "hello\n";
  /* block comment */
  if (argc >= 2 && argv[1] != 0) {
    return VALUE + msg[0];
  }
  return 'x';
}
