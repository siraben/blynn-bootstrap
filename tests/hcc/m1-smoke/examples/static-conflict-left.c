static int shared = 19;

static int helper(void)
{
  return shared;
}

int left_value(void)
{
  return helper();
}
