void save_mxcsr(unsigned int *p)
{
  __asm__ volatile("stmxcsr %0" : "=m"(*p));
}

void load_mxcsr(unsigned int *p)
{
  __asm__ volatile("ldmxcsr %0" : : "m"(*p));
}
