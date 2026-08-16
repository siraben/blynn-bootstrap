struct Pair {
  int first;
  int second;
};

int values[3] = { 3, 5, 9 };
struct Pair pair = { 7, 11 };

int *value_ptr = &values[1];
int *member_ptr = &pair.second;

int main() {
  if (*value_ptr != 5) return 1;
  if (*member_ptr != 11) return 2;
  return 0;
}
