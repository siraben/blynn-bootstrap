struct Bytes { char data[3]; };
struct Nested { char tag; struct Bytes bytes; char end; };
union BytesUnion { char data[5]; struct Bytes bytes; };
struct NestedUnion { char tag; union BytesUnion bytes; };
struct Value { int n; int *pointer; char text[4]; };
int change(struct Value value) {
  value.n = 9;
  value.text[0] = 'x';
  *value.pointer = 11;
  return value.n;
}
int change_union(union BytesUnion value) { value.data[0] = 9; return value.data[0]; }
void change_array(int data[1]) { data[0] = 13; }
struct Anonymous {
  char tag;
  union {
    struct { char prefix; struct { int nested; }; };
    long alternate;
  };
  int end;
};
int main(void) {
  struct Anonymous anonymous;
  anonymous.tag = 1;
  anonymous.prefix = 2;
  anonymous.nested = 17;
  anonymous.end = 23;
  if (anonymous.nested != 17 || anonymous.tag != 1 || anonymous.prefix != 2 || anonymous.end != 23) return 7;
  if ((char *)&anonymous.nested - (char *)&anonymous != sizeof(long) + sizeof(int)) return 8;
  int x = 7;
  int data[2] = {{3 + 4}, {x}};
  struct Value value = {x, &x, "ok"};
  struct Nested nested = {1, {{2, 3, 4}}, 5};
  union BytesUnion u = {{1, 2, 3, 4, 5}};
  int (*call)(struct Value) = change;
  if (data[0] != 7 || data[1] != 7 || value.n != 7 || *value.pointer != 7) return 1;
  if (value.text[0] != 'o' || value.text[3] != 0) return 2;
  if (sizeof(nested) != 5 || sizeof(struct NestedUnion) != 6) return 3;
  if ((char *)&nested.bytes - (char *)&nested != 1 || nested.end != 5) return 4;
  /* Aggregate values are copied; their pointees and decayed arrays are not. */
  if (call(value) != 9 || value.n != 7 || value.text[0] != 'o' || x != 11) return 5;
  if (change_union(u) != 9 || u.data[0] != 1) return 6;
  change_array(data);
  return data[0] != 13;
}
