#!/usr/bin/env bash
set -euo pipefail
compiler=$1
sources=$2
fixtures=$3
: "${CC:?host GCC is required explicitly for parity testing}"

# Run real executables from both compilers, not just assembly comparisons.
"$compiler" -f "$fixtures/semantics.c" -o grammar-test
"$CC" -std=c99 -O0 "$fixtures/semantics.c" -o gcc-test
./grammar-test > grammar.out
./gcc-test > gcc.out
printf 'OK\n' > expected.out
cmp expected.out grammar.out
cmp gcc.out grammar.out

# Pinned upstream regression cases for grammar and lowering, each requiring
# exit status zero as well as matching GCC's stdout (not merely equal failure).
for name in assignment cast_postfix_expr comma_conditions \
  conditional_expression constant_expressions for_loop_declaration \
  for_omitted_expressions function_pointer_arguments function_pointer_nested_call \
  global_function_pointer_init local_array_decay parenthesized_comma_expr \
  parenthesized_deref pointer_additive_expr pointer_arithmetic prefix_deref \
  prefix_postfix reverse_subscript static_variables; do
  file="$sources/test/run-pass/$name.c"
  "$compiler" --file="$file" --output=grammar-test --architecture=x86_64 --operating-system=Linux
  "$CC" -std=c99 -O0 "$file" -o gcc-test
  ./grammar-test > grammar.out
  ./gcc-test > gcc.out
  cmp gcc.out grammar.out
  echo "grammar parity: $name"
done

# This upstream fixture deliberately allows assignment in the third operand of
# ?: without parentheses (not ISO C). Test its fork contract, not GCC parity.
"$compiler" -f "$sources/test/run-pass/comma_expressions.c" -o grammar-extension
./grammar-extension

mkdir -p 'include dir' M2libc empty-path
printf '#define HEADER_VALUE 17\n' > 'include dir/value.h'
printf '#include "value.h"\nint helper(void) { return HEADER_VALUE + CLI_VALUE; }\n' > 'helper file.c'
printf 'int helper(void); int main(void) { return helper() != 42; }\n' > 'main file.c'
# The old adapter implicitly appended this file. It must not affect this one.
printf '#error must not be included implicitly\n' > M2libc/bootstrappable.c
PATH="$PWD/empty-path" "$compiler" --operating-system Linux --architecture amd64 \
  -I 'include dir' -D CLI_VALUE=25 -f 'helper file.c' --file 'main file.c' -o 'output file'
'./output file'
"$compiler" -I 'include dir' -D CLI_VALUE=25 --file='helper file.c' \
  --file='main file.c' --output='output file equals'
'./output file equals'

reject() {
  local status=0
  "$compiler" "$@" > reject.out 2> reject.err || status=$?
  [ "$status" = 2 ] || { echo "expected option error (2), got $status: $*" >&2; exit 1; }
  grep -q '^m2-planet-grammar-gcc-debug:' reject.err
}
reject
for option in -f --file -o --output --architecture --operating-system -I -D; do
  reject "$option"
  reject "$option" ''
  reject "$option" --bogus
done
for option in --file --output --architecture --operating-system; do
  reject "$option="
done
reject --bogus
reject --architecture sparc -f 'main file.c' -o bad
reject --architecture=aarch64 -f 'main file.c' -o bad
reject --operating-system FreeBSD -f 'main file.c' -o bad
reject --operating-system=Darwin -f 'main file.c' -o bad
reject -f 'main file.c'
reject -o bad
reject -f 'main file.c' -o bad --output=duplicate
[ ! -e bad ] && [ ! -e duplicate ]

# Compiler failures must propagate, preserve an existing destination, and clean
# intermediate files. This is separate from wrapper option validation.
printf '#error deliberate compiler error\n' > invalid.c
printf 'preserve me\n' > sentinel
cp sentinel unchanged
mkdir compiler-tmp
if TMPDIR="$PWD/compiler-tmp" "$compiler" -f invalid.c -o sentinel > invalid.out 2> invalid.err; then
  echo 'invalid source unexpectedly compiled' >&2
  exit 1
fi
cmp unchanged sentinel
[ -z "$(ls -A compiler-tmp)" ]
echo 'grammar wrapper tests passed'
