#!/bin/sh
# Preprocessing behavior shared by host and concatenated compiler smoke gates.
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
