static int internal_value = 25;

static int helper(void)
{
  return 17;
}

int main(void)
{
  return helper() + internal_value - 42;
}
