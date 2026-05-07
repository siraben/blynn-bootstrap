int add(int a, int b) {
  return a + b;
}

typedef struct {
  int field;
} Item;

static void *(*reallocator)(void *, unsigned long);
static const char *const templates[] = { "x", "y" };
int width = sizeof ((Item*)0)->field;

int global = 7;
