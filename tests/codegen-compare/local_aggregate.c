struct pair {
  int a;
  int b;
};

int use_pair(int seed)
{
  struct pair p = { 3, 9 };
  struct pair q;
  q = p;
  return q.a + q.b + seed;
}

int main()
{
  return use_pair(5);
}
