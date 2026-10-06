int main(void) {
  unsigned long bits;

  if (sizeof(1U) != 4)
    return 1;
  if (sizeof(1UL) != sizeof(unsigned long) ||
      sizeof(1LU) != sizeof(unsigned long) || sizeof(1L) != sizeof(long))
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

  /* Exercise the highest unsigned bit on both ILP32 and LP64. The 36-bit
     mask regression lives in wide-static-memory on 64-bit targets. */
  bits = (1UL << (sizeof(long) * 8 - 1)) | (1UL << 15);
  bits &= ~(1UL << 15);
  if (bits != (1UL << (sizeof(long) * 8 - 1)))
    return 8;
  bits >>= 1;
  if (bits != (1UL << (sizeof(long) * 8 - 2)))
    return 9;

  return 0;
}
