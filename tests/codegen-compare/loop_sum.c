int loop_sum(int n)
{
  int i;
  int acc;
  i = 0;
  acc = 0;
  while (i < n) {
    acc = acc + i;
    i = i + 1;
  }
  return acc;
}

int main()
{
  return loop_sum(10);
}
