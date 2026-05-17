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

long double
ldexpl (long double value, int exponent)
{
  return (long double) ldexp ((double) value, exponent);
}
