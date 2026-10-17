/* Final TinyCC + installed libc/libtcc1 regression, not a stage1 FP claim.
   The bootstrap targets are LP64 with IEEE-754 binary64 doubles. */
#include <stdlib.h>

static int is_two64(double value)
{
  union { double d; unsigned long u; } bits;
  bits.d = value;
  return bits.u == 0x43f0000000000000UL;
}

double runtime_large_literal = 18446744073709551616.0;

int main(void)
{
  volatile unsigned long long high = 9223372036854775808ULL;
  union { double d; unsigned long u; } converted;
  char *end;
  if (!is_two64(runtime_large_literal)) return 1;
  converted.d = (double)high;
  if (converted.u != 0x43e0000000000000UL) return 2;
  /* ULONG_MAX also exercises overflow-free normalization. */
  if (!is_two64(strtod("18446744073709551615", &end)) || *end) return 3;
  if (!is_two64(strtod("18446744073709551616.0!", &end)) || *end != '!') return 4;
  if (!is_two64(strtod("18446744073709551617", &end)) || *end) return 5;
  converted.d = strtod("1e999999999999999999999999", &end);
  if (converted.u != 0x7ff0000000000000UL || *end) return 6;
  if (strtod("1e-999999999999999999999999", &end) != 0.0 || *end) return 7;
  return 0;
}
