int both_nonzero(int a, int b)
{
  return a && b;
}

int either_nonzero(int a, int b)
{
  return a || b;
}

int main()
{
  return both_nonzero(1, 2) + either_nonzero(0, 4);
}
