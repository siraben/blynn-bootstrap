int main(void) {
  unsigned long bits;

  if (sizeof(1U) != 4)
    return 1;
  if (sizeof(1UL) != 8 || sizeof(1LU) != 8 || sizeof(1L) != 8)
    return 2;
  if (sizeof(1ULL) != 8 || sizeof(1LLU) != 8 || sizeof(1LL) != 8)
    return 3;
  if (sizeof(2147483648) != 8 || sizeof(2147483648U) != 4)
    return 4;
  if (sizeof(0x80000000) != 4 || sizeof(0xffffffff) != 4)
    return 5;
  if (sizeof(0x100000000) != 8 || sizeof(4294967295) != 8)
    return 6;
  if (sizeof(9223372036854775808ULL) != 8)
    return 7;

  bits = (1UL << 36) | (1UL << 31);
  bits &= ~(1UL << 31);
  if (bits != (1UL << 36))
    return 8;

  return 0;
}
