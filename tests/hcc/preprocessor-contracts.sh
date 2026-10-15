# Sourced by compiler smoke; uses only its compiler paths and POSIX shell.
pp_contract_contains() {
  pp_pattern=$1
  pp_file=$2
  pp_found=0
  while IFS= read -r pp_line; do
    case "$pp_line" in *"$pp_pattern"*) pp_found=1; break ;; esac
  done < "$pp_file"
  if test "$pp_found" != 1; then
    echo "$pp_file: expected $pp_pattern" >&2
    exit 1
  fi
}

"$HCPP" "$TESTS_DIR/pp-contract-inactive.c" > pp-contract-inactive.i
pp_contract_contains 'int pp_contract_inactive ;' pp-contract-inactive.i
"$HCC1" --check pp-contract-inactive.i

"$HCPP" "$TESTS_DIR/pp-contract-macros.c" > pp-contract-macros.i
pp_contract_contains 'pp_contract_nested = ( ( ( ( 1 ) + 1 ) ) + 1 )' pp-contract-macros.i
pp_contract_contains 'pp_contract_suffix = ( ( 1 ) + 1 )' pp-contract-macros.i
pp_contract_contains 'int A ;' pp-contract-macros.i
pp_contract_contains 'SELF ( 1 )' pp-contract-macros.i
pp_contract_contains '2 * 9 * g' pp-contract-macros.i
pp_contract_contains 'one twothree four' pp-contract-macros.i

"$HCPP" "$TESTS_DIR/pp-contract-include.c" > pp-contract-include.i
pp_contract_contains 'int pp_contract_include ;' pp-contract-include.i
pp_contract_contains 'int pp_contract_continued ;' pp-contract-include.i
"$HCC1" --check pp-contract-include.i
if "$HCPP" "$TESTS_DIR/pp-contract-bad-include.c" > pp-contract-bad-include.i 2> pp-contract-bad-include.err; then
  echo 'invalid active include unexpectedly accepted' >&2
  exit 1
fi
pp_contract_contains 'invalid active #include operand' pp-contract-bad-include.err

"$HCPP" "$TESTS_DIR/pp-contract-stringify.c" > pp-contract-stringify.i
pp_contract_contains 'pp_adjacent = "a+b"' pp-contract-stringify.i
pp_contract_contains 'pp_space = "a + b"' pp-contract-stringify.i
pp_contract_contains 'pp_comment = "a +b"' pp-contract-stringify.i
pp_contract_contains 'pp_expand = "a+b"' pp-contract-stringify.i
pp_contract_contains 'pp_empty_object = "a +b"' pp-contract-stringify.i
pp_contract_contains 'pp_empty_function = "a +b"' pp-contract-stringify.i
pp_contract_contains 'pp_empty_argument = "a +b"' pp-contract-stringify.i
pp_contract_contains 'pp_wrap = "a+b + c"' pp-contract-stringify.i
pp_contract_contains 'pp_variadic = "a ,b, c"' pp-contract-stringify.i
pp_contract_contains 'pp_escape = "\"a\\\\b\""' pp-contract-stringify.i
pp_contract_contains 'pp_splice = "a+b"' pp-contract-stringify.i
"$HCC1" --check pp-contract-stringify.i

"$HCPP" "$TESTS_DIR/pp-contract-arithmetic.c" > pp-contract-arithmetic.i
pp_contract_contains 'int pp_contract_arithmetic ;' pp-contract-arithmetic.i
"$HCC1" --check pp-contract-arithmetic.i
"$HCC1" --m1-ir -o pp-contract-arithmetic.hccir pp-contract-arithmetic.i
"$HCC_M1" pp-contract-arithmetic.hccir pp-contract-arithmetic.M1
