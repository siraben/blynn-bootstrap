/*
 * Mes libc's ldexp stubs are not enough for the HCC-seeded TinyCC bootstrap.
 * TinyCC applies binary exponents while parsing floating constants, and musl's
 * coefficient-table literals expose the bad values downstream.  These helpers
 * provide the small, predictable power-of-two scaling surface needed until the
 * real libc is built.
 */

/* Scale a double by a signed power of two using only basic arithmetic. */
double
ldexp (double value, int exponent)
{
  while (exponent > 0)
    {
      value = value * 2.0;
      exponent = exponent - 1;
    }
  while (exponent < 0)
    {
      value = value / 2.0;
      exponent = exponent + 1;
    }
  return value;
}

/* Bootstrap limitation: ldexpl reuses the double scaling helper. */
long double
ldexpl (long double value, int exponent)
{
  return (long double) ldexp ((double) value, exponent);
}
