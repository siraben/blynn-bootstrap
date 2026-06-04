int classify(int x)
{
  if (x < 0) return -1;
  if (x == 0) return 0;
  if (x < 10) return x + 3;
  return x - 7;
}

int main()
{
  return classify(8);
}
