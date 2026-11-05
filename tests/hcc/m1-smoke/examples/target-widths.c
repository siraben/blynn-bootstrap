/* The runner checks 8 on i386 and 16 on the 64-bit targets. */
struct layout { char c; long value; void *ptr; };
int main(void)
{
  long values[2];
  struct layout s;
  long *p = values;
  if (sizeof(int) != 4 || sizeof(long long) != 8) return 90;
  if (sizeof(long) != sizeof(void *)) return 91;
  if (sizeof(s) != 3 * sizeof(long)) return 92;
  if ((char *)&s.value - (char *)&s != sizeof(long)) return 93;
  if ((char *)&s.ptr - (char *)&s != 2 * sizeof(long)) return 94;
  p[1] = 37;
  if (*(p + 1) != 37 || (char *)(p + 1) - (char *)p != sizeof(long)) return 95;
  return sizeof(long) + sizeof(void *);
}
