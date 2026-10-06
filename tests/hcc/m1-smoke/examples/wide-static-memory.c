/* i386 currently diagnoses 64-bit memory loads. Other backends must execute
   the negative static initializer and target-wide mask regressions. */
static long long static_sll = -65539LL;

int main(void) {
  unsigned long bits;
  if (static_sll != -65539LL) return 1;
  bits = (1UL << 36) | (1UL << 31);
  bits &= ~(1UL << 31);
  if (bits != (1UL << 36)) return 2;
  return 0;
}
