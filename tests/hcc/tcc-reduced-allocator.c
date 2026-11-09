/* The reduced libc intentionally uses unsigned allocation sizes. */
void *malloc(unsigned size);
void *calloc(unsigned count, unsigned size);
void free(void *ptr);
void exit(int code);
#define CHECK(x, code)                                                                             \
  if (!(x)) return code
int main(void) {
  char *first = malloc(17);
  char *zeroed = calloc(3, 7);
  char *next;
  int i;
  CHECK(first && zeroed && zeroed == first + 17, 1);
  for (i = 0; i < 17; i = i + 1) first[i] = i + 1;
  for (i = 0; i < 21; i = i + 1) CHECK(zeroed[i] == 0, 2);
  free(first);
  next = malloc(1);
  CHECK(next == zeroed + 21, 3);
  for (i = 0; i < 17; i = i + 1) CHECK(first[i] == i + 1, 4);
  exit(0);
  return 1;
}
