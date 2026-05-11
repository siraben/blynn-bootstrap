long passthrough_high_reg(long x)
{
  register long r __asm__("%r8") = x;
  __asm__ volatile("" : "+r"(r));
  return r;
}
