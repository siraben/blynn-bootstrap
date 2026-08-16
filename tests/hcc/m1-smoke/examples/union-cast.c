/* GNU C permits a scalar to be cast to a union containing a compatible
 * member.  GCC uses this idiom to remove qualifiers without aliasing through
 * an incompatible pointer type. */

static const char **qualifier_cast(char **value) {
  return ((union {
    char **from;
    const char **to;
  }) value).to;
}

int main(void) {
  char *value = "union cast";
  char **source = &value;
  const char **cast = qualifier_cast(source);
  return cast == (const char **)source && cast[0] == value ? 0 : 1;
}
