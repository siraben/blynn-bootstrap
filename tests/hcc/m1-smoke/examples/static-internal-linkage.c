static int internal_value = 25;

static int helper(void)
{
  if (__func__[0] != 'h') return 0;
  return 17;
}

int main(void)
{
  return helper() + internal_value - 42;
}
