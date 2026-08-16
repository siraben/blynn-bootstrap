static int shared = 23;

static int helper(void)
{
  return shared;
}

int right_value(void)
{
  return helper();
}
