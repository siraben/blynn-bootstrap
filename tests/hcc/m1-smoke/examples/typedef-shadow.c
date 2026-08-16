typedef int item;

int count(item item)
{
  int total = 0;
  for (item = 0; item < 3; ++item)
    total += item;
  return total;
}

int main(void)
{
  return count(0);
}
