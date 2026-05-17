/*
 * This file replaces Mes libc's floating conversion stubs only for the
 * HCC-seeded TinyCC bootstrap.  Upstream TinyCC parses C floating constants by
 * asking libc to convert mantissas and apply exponents; if the bootstrap libc
 * returns truncated values, the self-rebuilt TinyCC can preserve those bad
 * constants and later miscompile musl.  The implementation here is deliberately
 * small and covers the integer-valued decimal and hexadecimal literals needed
 * on that path, including mantissas wider than 32 bits.
 */

union hcc_strtod_double_bits
{
  unsigned long u;
  double d;
};

/* Reinterpret an IEEE-754 bit pattern as a double without relying on libm. */
static double
hcc_strtod_double_from_bits (unsigned long bits)
{
  union hcc_strtod_double_bits out;
  out.u = bits;
  return out.d;
}

/* Build a normalized double from an unsigned integer mantissa and base-2 exponent. */
static double
hcc_strtod_double_from_scaled_uint64 (unsigned long mantissa, int exp2)
{
  unsigned long hidden = 0x10000000000000UL;
  unsigned long overflow = 0x20000000000000UL;
  unsigned long fraction;
  int exponent;

  if (mantissa == 0)
    return hcc_strtod_double_from_bits (0);
  while (mantissa >= overflow)
    {
      mantissa = (mantissa + 1) >> 1;
      exp2 = exp2 + 1;
    }
  while (mantissa < hidden)
    {
      mantissa = mantissa << 1;
      exp2 = exp2 - 1;
    }

  exponent = exp2 + 52;
  if (exponent <= -1023)
    return hcc_strtod_double_from_bits (0);
  if (exponent >= 1024)
    return hcc_strtod_double_from_bits (0x7ff0000000000000UL);

  fraction = mantissa - hidden;
  return hcc_strtod_double_from_bits ((((unsigned long) (exponent + 1023)) << 52)
                                      | fraction);
}

/* Convert one ASCII digit accepted by the decimal and hexadecimal parsers. */
static int
hcc_strtod_digit_value (int c)
{
  if (c >= '0' && c <= '9')
    return c - '0';
  if (c >= 'a' && c <= 'f')
    return c - 'a' + 10;
  if (c >= 'A' && c <= 'F')
    return c - 'A' + 10;
  return 99;
}

/*
 * Parse the absolute value after optional sign handling.
 *
 * Mes libc calls this helper directly, and TinyCC reaches it through strtod.
 * The parser handles integer and fractional digits plus decimal exponents,
 * which is enough for the reduced musl/TinyCC bootstrap constants.
 */
double
abtod (char const **p, int base)
{
  char const *s = *p;
  unsigned long integer = 0;
  double out;
  int sign = 1;
  int digit;

  if (!base)
    base = 10;
  if (*s == '-')
    {
      sign = -1;
      s++;
    }
  else if (*s == '+')
    s++;

  while ((digit = hcc_strtod_digit_value (*s)) < base)
    {
      integer = integer * (unsigned long) base + (unsigned long) digit;
      s++;
    }

  out = hcc_strtod_double_from_scaled_uint64 (integer, 0);
  if (*s == '.')
    {
      double scale = (double) base;
      s++;
      while ((digit = hcc_strtod_digit_value (*s)) < base)
        {
          out = out + (double) digit / scale;
          scale = scale * (double) base;
          s++;
        }
    }
  if (*s == 'e' || *s == 'E')
    {
      int exp_sign = 1;
      long exp = 0;
      s++;
      if (*s == '-')
        {
          exp_sign = -1;
          s++;
        }
      else if (*s == '+')
        s++;
      while (*s >= '0' && *s <= '9')
        {
          exp = exp * 10 + (*s - '0');
          s++;
        }
      while (exp > 0)
        {
          out = exp_sign < 0 ? out / 10.0 : out * 10.0;
          exp--;
        }
    }

  *p = s;
  return sign < 0 ? -out : out;
}

/* Parse a decimal or 0x-prefixed hexadecimal floating literal. */
double
strtod (char const *string, char **tailptr)
{
  int base = 10;
  char const *p = string;

  if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X'))
    {
      p += 2;
      base = 16;
    }
  if (tailptr)
    {
      *tailptr = (char *) p;
      return abtod ((char const **) tailptr, base);
    }
  return abtod (&p, base);
}

/* strtof shares the bootstrap strtod parser and narrows the result. */
float
strtof (char const *string, char **tailptr)
{
  return (float) strtod (string, tailptr);
}

/* Bootstrap limitation: this is not a general target-ABI strtold. */
long double
strtold (char const *string, char **tailptr)
{
  return (long double) strtod (string, tailptr);
}
