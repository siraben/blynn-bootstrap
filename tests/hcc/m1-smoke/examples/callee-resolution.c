int count;
int order;
int record(int value) { order = order * 10 + value; return 0; }
long target(void) { count += 100; return 99; }
int next(void) { ++count; return count < 4; }
int (*external_call)(void) = next;
extern int (*external_call)(void);
int reuse(void) { int (*target)(void) = next; return target(); }
int before_shadow(void) {
  if (target() != 99) return 1;
  count = 0;
  int (*target)(void) = next;
  return target() != 1;
}
int switch_shadow(void) {
  count = 0;
  switch (0) {
    case 0: ;
      int (*target)(void) = next;
      target();
      break;
  }
  return target() != 99 || count != 101;
}
int ignored_calls(void) {
  int seen = 0;
  oputs(exit(++seen));
  eputs(_exit(++seen));
  int (*a)(int) = exit;
  int (*b)(int) = _exit;
  return seen != 0 || !a || !b;
}
int forward(void) { return later(); }
int later(void) { return 7; }
int main(void) {
  if (ignored_calls()) return 15;
  do { sizeof(exit(0)); int (*p)(int) = exit; if (!p) return 14; } while ((exit, 0));
  int values[2];
  int *position = (record(1), 1) + (record(2), values);
  if (order != 12 || position != values + 1) return 13;
  if (before_shadow() != 0 || switch_shadow() != 0) return 5;
  count = 0;
  int NULL = 7;
  int (*target)(void) = next;
  if (NULL != 7 || target() != 1 || count != 1) return 1;
  target();
  if (count != 2 || reuse() != 1 || count != 3) return 2;
  count = 0;
  for (int (*target)(void) = next; target(); target()) {
    if (count == 1) target();
  }
  if (count != 4 || external_call() != 0 || count != 5) return 3;
  {
    int (*oputs)(void) = next;
    oputs();
    if (count != 6) return 6;
  }
  /* Unbound bootstrap diagnostic calls intentionally discard their arguments. */
  oputs(++count);
  if (count != 6) return 7;
  count = 4;
  {
    int (*exit)(void) = next;
    int (*FUNCTION_local)(void) = sizeof(FUNCTION_local() == 0) ? next : next;
    if (sizeof(sizeof((exit() || FUNCTION_local()) ? ++count : next())) != sizeof(sizeof(int))) return 8;
    if (exit() != 0 || count != 5) return 9;
  }
  /* Nested sizeof must introduce calls even when typing skips their operands. */
  if (sizeof(sizeof((exit(++count) == 0 || _exit(++count)) ? next() : ++count)) != sizeof(sizeof(int))) return 10;
  if (sizeof(exit(++count)) != sizeof(long) || forward() != 7) return 4;
  int (*finish)(int) = exit;
  int (*fail)(int) = _exit;
  if (!finish || !fail) return 12;
  if (count != 5) return 11;
  return 0;
}
