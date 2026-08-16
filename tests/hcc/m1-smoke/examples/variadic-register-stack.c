typedef void *va_list;

#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_end(ap) __builtin_va_end(ap)
#define va_copy(dst, src) __builtin_va_copy(dst, src)
#define va_arg(ap, type) __builtin_va_arg(ap, type)

static int sum_nine(int marker, ...) {
  va_list ap;
  va_list copy;
  int first;
  int copied;
  int total;

  va_start(ap, marker);
  first = va_arg(ap, int);
  va_copy(copy, ap);
  copied = va_arg(copy, int);
  total = first + va_arg(ap, int);
  total = total + va_arg(ap, int);
  total = total + va_arg(ap, int);
  total = total + va_arg(ap, int);
  total = total + va_arg(ap, int);
  total = total + va_arg(ap, int);
  total = total + va_arg(ap, int);
  total = total + va_arg(ap, int);
  va_end(copy);
  va_end(ap);
  return total == 45 && copied == 2;
}

int main(void) {
  return sum_nine(0, 1, 2, 3, 4, 5, 6, 7, 8, 9) ? 0 : 1;
}
