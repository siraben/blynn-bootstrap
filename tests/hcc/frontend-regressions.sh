#!/bin/sh
# Behavior checks shared by the host and concatenated compiler build smoke gate.
set -eu
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

reject() {
  tool=$1
  expected=$2
  input=$3
  shift 3
  if "$tool" "$@" "$input" > "$work/out" 2> "$work/err"; then
    echo "frontend-regressions: unexpectedly accepted $input" >&2
    exit 1
  fi
  if ! grep -F "$expected" "$work/err" >/dev/null; then
    cat "$work/err" >&2
    echo "frontend-regressions: expected $expected" >&2
    exit 1
  fi
}

printf 'int x;\n  /* unclosed\n' > "$work/comment.c"
reject "$HCPP" ':2:3: unterminated block comment' "$work/comment.c"
reject "$HCC1" ':2:3: unterminated block comment' "$work/comment.c"
printf '#if 0\n/* unclosed\n' > "$work/comment.c"
reject "$HCPP" ':2:1: unterminated block comment' "$work/comment.c"

for directive in ifdef ifndef; do
  for prefix in '' '#if 0'; do
    printf '%s\n#%s\n#include "missing-after-invalid.h"\n' "$prefix" "$directive" > "$work/operand.c"
    reject "$HCPP" "#$directive without macro name" "$work/operand.c"
  done
done
for directive in define undef; do
  printf '#%s\n#include "missing-after-invalid.h"\n' "$directive" > "$work/operand.c"
  reject "$HCPP" "#$directive without macro name" "$work/operand.c"
done
printf '#else\n' > "$work/unmatched.c"
reject "$HCPP" '#else without #if' "$work/unmatched.c"

printf '#include 42\n' > "$work/include.c"
reject "$HCPP" 'invalid active #include operand' "$work/include.c"
printf '#include "recursive.h"\n' > "$work/recursive.h"
reject "$HCPP" 'include nesting exceeds 200' "$work/recursive.h"

# Lazy implicit registration must still reject backend-reserved function names,
# and the transactional emitter must not publish the already-lowered function.
cat > "$work/reserved.i" <<'EOF'
int first(void) { return 0; }
int main(void) { return FUNCTION_reserved(); }
EOF
reject "$HCC1" 'uses a reserved HCC label prefix' "$work/reserved.i" -o "$work/reserved.hccir"
[ ! -s "$work/reserved.hccir" ]
printf 'int main(void) { return asm("nop"); }\n' > "$work/asm.i"
reject "$HCC1" 'unknown identifier: asm' "$work/asm.i" -o "$work/asm.hccir"

# Discarded bootstrap diagnostics retain implicit declarations, but local objects
# still shadow function names and their argument values must never execute.
for diagnostic in oputs eputs; do
  printf 'int count; int main(void) { %s(main(exit(++count))); int (*p)(int) = exit; return count; }\n' "$diagnostic" > "$work/diagnostic.i"
  "$HCC1" --m1-ir -o "$work/diagnostic.hccir" "$work/diagnostic.i"
  if grep -E '^(19|20) ' "$work/diagnostic.hccir" >/dev/null; then
    echo "frontend-regressions: discarded diagnostic emitted a call" >&2
    exit 1
  fi
  printf 'int next(void){return 0;} int main(void){{int (*exit)(void)=next; %s(exit());} int (*p)(int)=exit; return 0;}\n' "$diagnostic" > "$work/diagnostic-shadow.i"
  reject "$HCC1" 'unknown identifier: exit' "$work/diagnostic-shadow.i" --m1-ir -o "$work/diagnostic-shadow.hccir"
done

# Every case starts a fresh translation unit: an earlier sizeof call must not
# mask a missed introduction in another skipped typing branch.
while IFS= read -r operand; do
  printf 'int count; int main(void) { sizeof(%s); int (*p)(int) = exit; return 0; }\n' "$operand" > "$work/sizeof.i"
  "$HCC1" --m1-ir -o "$work/sizeof.hccir" "$work/sizeof.i"
  grep -F 'Fexit' "$work/sizeof.hccir" >/dev/null
  if grep -E '^(19|20) ' "$work/sizeof.hccir" >/dev/null; then
    echo "frontend-regressions: sizeof emitted a call for $operand" >&2
    exit 1
  fi
done <<'EOF'
exit(++count) == 0
exit(++count) != 0
exit(++count) < 0
exit(++count) && 0
0 || exit(++count)
exit(++count) ? 1 : 0
1 ? exit(++count) : 0
0 ? 0 : exit(++count)
sizeof(sizeof(exit(++count) == 0 || (0 ? 0 : exit(++count))))
!exit(++count)
(int)exit(++count)
((int *)0)[exit(++count)]
1 << exit(++count)
1 >> exit(++count)
(exit(++count), 1)
count = exit(++count)
count += exit(++count)
main(exit(++count))
sizeof(int[exit(++count)])
sizeof((struct { int field[exit(++count)]; } *)0)
EOF

# An unevaluated call through a local object must not invent a global function.
cat > "$work/shadow.i" <<'EOF'
int next(void) { return 0; }
int main(void) {
  { int (*exit)(void) = next; sizeof(sizeof(exit() == 0 || exit())); }
  int (*p)(int) = exit;
  return 0;
}
EOF
reject "$HCC1" 'unknown identifier: exit' "$work/shadow.i" -o "$work/shadow.hccir"
# A declaration's own object is already in scope inside its initializer.
cat > "$work/self-shadow.i" <<'EOF'
int next(int value) { return value; }
int main(void) {
  { int (*exit)(int) = sizeof(exit(0) == 0) ? next : next; }
  int (*p)(int) = exit;
  return 0;
}
EOF
reject "$HCC1" 'unknown identifier: exit' "$work/self-shadow.i" -o "$work/self-shadow.hccir"
# Lowering construction follows source order, independently of CFG block order.
# Fresh processes prevent a previous case's implicit function identity leaking in.
while IFS= read -r body; do
  printf 'int main(void) { %s }\n' "$body" > "$work/order.i"
  "$HCC1" --m1-ir -o "$work/order.hccir" "$work/order.i"
done <<'EOF'
do { sizeof(exit(0)); } while ((exit, 0)); return 0;
do { sizeof(exit(0)); int (*p)(int) = exit; } while ((exit, 0)); return 0;
if (sizeof(exit(0))) { return (exit, 0); } return 0;
if (0) { sizeof(exit(0)); } else { return (exit, 0); } return 0;
while (sizeof(exit(0))) { return (exit, 0); } return 0;
for (sizeof(exit(0)); (exit, 0); ) {} return 0;
for (; sizeof(exit(0)); (exit, 0)) {} return 0;
for (; 0; sizeof(exit(0))) { return (exit, 0); } return 0;
switch (0) { case 0: sizeof(exit(0)); break; case 1: return (exit, 0); } return 0;
return (sizeof(exit(0)), (exit, 0));
return (sizeof(exit(0)), 0) + (int *)(exit, 0) == 0;
return (sizeof(exit(0)), 0) / ((exit, 0));
return sizeof((exit, exit(0)));
EOF

# Neither later sizeof boundaries nor speculative type queries predeclare calls.
while IFS= read -r body; do
  printf 'int main(void) { %s }\n' "$body" > "$work/order.i"
  reject "$HCC1" 'unknown identifier: exit' "$work/order.i" -o "$work/order.hccir"
done <<'EOF'
return (exit, exit(0));
return (exit, sizeof(exit(0)));
return (exit, 0) + exit(0);
return (exit, 0) - exit(0);
return (exit, 0) / exit(0);
return (exit, 0) % exit(0);
return (exit, 0) + (int *)(sizeof(exit(0)), 0);
return exit == sizeof(exit(0));
return exit && sizeof(exit(0));
return exit || sizeof(exit(0));
return exit ? 0 : sizeof(exit(0));
if (exit && sizeof(exit(0))) return 1; return 0;
if (exit || sizeof(exit(0))) return 1; return 0;
if (0) { return exit == 0; } else { sizeof(exit(0)); } return 0;
while (exit == 0) { sizeof(exit(0)); } return 0;
do { return exit == 0; } while (sizeof(exit(0))); return 0;
for (; exit == 0; sizeof(exit(0))) {} return 0;
for (; 0; exit == 0) { sizeof(exit(0)); } return 0;
switch (0) { case 0: return exit == 0; case sizeof(exit(0)): return 0; } return 0;
switch (0) { case 0: ; int (*exit)(int) = 0; break; case sizeof(exit(0)): break; } return exit == 0;
EOF

# Inline definitions also survive constant-template and skipped-type paths.
while IFS= read -r body; do
  printf 'int main(void) { %s }\n' "$body" > "$work/aggregate.i"
  "$HCC1" --m1-ir -o "$work/aggregate.hccir" "$work/aggregate.i"
done <<'EOF'
int a[1] = { sizeof(struct A { int n; }) }; return sizeof(struct A) != 4;
int a[1] = { sizeof(exit(0)) }; int (*p)(int) = exit; return p == 0;
int a[1] = { 0 ? sizeof(struct A { int n; }) : 0 }; return sizeof(struct A) != 4;
switch (0) { case 0: sizeof(struct A { int n; }); break; case sizeof(struct A): return 0; } return 0;
return ((struct A { int n; } *)0, sizeof(struct A)) != 4;
return (sizeof(struct A { int n; }), ((struct A *)0)->n) + 0;
EOF

cat > "$work/header with spaces.h" <<'EOF'
#pragma once
#ifdef HEADER_SEEN
#error pragma once failed
#endif
#define HEADER_SEEN
#undef VALUE
#define VALUE 7
EOF
cat > "$work/valid.c" <<'EOF'
#define VALUE 1
#define HEADER "header with spaces.h"
#include HEADER
#include HEADER
#if VALUE == 7
#elif 1/0
#error ineligible elif evaluated
#else
#error header environment did not propagate
#endif
#if 0
#include "missing-inactive.h"
#define
#undef
#if nonsense ( tokens
#endif
#endif
#define COMMENT/**/(x) x
#define STRING(x) #x
#define EXPAND(x) STRING(x)
char *replacement = EXPAND(COMMENT);
/* #if 0
   #include "commented.h" */
char *quoted = "/* not a comment */ // neither";
int/**/x = VALUE;
EOF
cp "$work/valid.c" "$work/input.c"
printf '#define CONTINUED \\\r\n7\nint continued = CONTINUED;\n' >> "$work/input.c"
"$HCPP" "$work/input.c" > "$work/input.i"
"$HCC1" --check "$work/input.i"
grep -F '"/* not a comment */ // neither"' "$work/input.i" >/dev/null
grep -F '"(x) x"' "$work/input.i" >/dev/null
grep -F 'int x = 7' "$work/input.i" >/dev/null
grep -F 'int continued = 7' "$work/input.i" >/dev/null

# Removing a long comment must retain the following token's column.
printf 'int x; /* comment */ @\n' > "$work/column.c"
reject "$HCC1" ':1:22: unexpected character: @' "$work/column.c"
printf 'frontend-regressions: passed\n'
