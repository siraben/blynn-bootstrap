void parse_number_float_constants(void) {
  unsigned int bn[4];
  long double d;

  bn[0] = 1;
  bn[1] = 2;
  bn[2] = 3;
  bn[3] = 4;
  d = (long double)bn[3] * 79228162514264337593543950336.0L
    + (long double)bn[2] * 18446744073709551616.0L
    + (long double)bn[1] * 4294967296.0L
    + (long double)bn[0];
  (void)d;
}
