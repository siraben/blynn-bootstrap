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

if "$HCPP" "$TESTS_DIR/pp-contract-object-location.c" > pp-contract-object-location.i 2> pp-contract-object-location.err; then
  echo 'invalid macro invocation unexpectedly accepted' >&2
  exit 1
fi
pp_contract_contains ':6:1: wrong number of macro arguments' pp-contract-object-location.err
if "$HCPP" "$TESTS_DIR/pp-contract-argument-location.c" > pp-contract-argument-location.i 2> pp-contract-argument-location.err; then
  echo 'invalid substituted argument invocation unexpectedly accepted' >&2
  exit 1
fi
pp_contract_contains ':6:6: wrong number of macro arguments' pp-contract-argument-location.err

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

"$HCPP" "$TESTS_DIR/pp-contract-trailing.c" > pp-contract-trailing.i
pp_contract_contains 'pp_trailing = "a b"' pp-contract-trailing.i
pp_contract_contains 'pp_trailing_macro = "a b"' pp-contract-trailing.i
pp_contract_contains 'pp_trailing_nested = "a b"' pp-contract-trailing.i
pp_contract_contains 'pp_trailing_adjacent = "a+b"' pp-contract-trailing.i
pp_contract_contains 'pp_trailing_both = "a b"' pp-contract-trailing.i
pp_contract_contains 'pp_trailing_left = "a bb"' pp-contract-trailing.i
pp_contract_contains 'pp_trailing_chain = "a bb"' pp-contract-trailing.i
pp_contract_contains 'pp_trailing_call = "b"' pp-contract-trailing.i
pp_contract_contains 'pp_empty_adjacent = "z()b"' pp-contract-trailing.i
pp_contract_contains 'pp_empty_prescan = "a+ b"' pp-contract-trailing.i
pp_contract_contains 'pp_empty_leading = "a+b"' pp-contract-trailing.i
"$HCC1" --m1-ir -o pp-contract-trailing.hccir pp-contract-trailing.i
"$HCC_M1" pp-contract-trailing.hccir pp-contract-trailing.M1

"$HCPP" "$TESTS_DIR/pp-contract-arithmetic.c" > pp-contract-arithmetic.i
pp_contract_contains 'int pp_contract_arithmetic ;' pp-contract-arithmetic.i
"$HCC1" --check pp-contract-arithmetic.i
"$HCC1" --m1-ir -o pp-contract-arithmetic.hccir pp-contract-arithmetic.i
"$HCC_M1" pp-contract-arithmetic.hccir pp-contract-arithmetic.M1

"$HCPP" "$TESTS_DIR/pp-contract-folded.c" > pp-contract-folded.i
"$HCC1" --m1-ir -o pp-contract-folded.hccir pp-contract-folded.i
# Check actual lowered bytes, not merely frontend acceptance.
for pp_expected in 'HCCIR 1' 'D pp_contract_quotient' 'b 254' 'b 255' 'b 255' 'b 255' E \
  'D pp_contract_remainder' 'b 255' 'b 255' 'b 255' 'b 255' E \
  'D pp_contract_bit31' 'z 3' 'b 128' E \
  'D pp_contract_shift' 'b 255' 'b 255' 'b 255' 'b 255' E; do
  IFS= read -r pp_actual
  if test "$pp_actual" != "$pp_expected"; then
    echo "folded constant: expected $pp_expected, got $pp_actual" >&2
    exit 1
  fi
done < pp-contract-folded.hccir
"$HCC_M1" pp-contract-folded.hccir pp-contract-folded.M1

# Ordinary constants use the selected target, not #if's intmax model.
for pp_target in amd64 i386 aarch64 riscv64; do
  pp_model=1
  if test "$pp_target" = i386; then pp_model=0; fi
  # In #if, 1U is uintmax_t, so -1L < 1U is false on every target.
  # Use an independent expression that is true only in the #if model.
  printf '%s\n' '#if (~0U <= 4294967295U) || (-1L < 1U)' \
    '#error wrong preprocessing integer model' '#endif' > constants-pp.c
  "$HCPP" constants-pp.c > constants-pp.i
  # The ordinary input is intentionally not preprocessed: no target macros
  # are needed to select the expected result.
  printf '%s\n' 'enum { constants_target_enum = -1L < 1U };' \
    "_Static_assert(constants_target_enum == $pp_model, \"enum model\");" \
    "_Static_assert((-1L < 1U) == $pp_model, \"ordinary model\");" \
    '_Static_assert(4294967296ULL, "wide truth value");' \
    '_Static_assert(~0U == 4294967295U, "ordinary uint32");' \
    'enum { constants_small = 1ULL, constants_boot32 = 0xffffffffU, constants_boot64 = 0xffffffffffffffffULL };' \
    '_Static_assert(~constants_small < 0, "representable enumerators have int type");' \
    '_Static_assert(constants_boot32 == 4294967295U, "bootstrap uint32 enumerator");' \
    '_Static_assert(constants_boot64 / 3ULL == 6148914691236517205ULL, "bootstrap uint64 enumerator");' \
    > constants-target.c
  "$HCC1" --target "$pp_target" -o "constants-target-$pp_target.hccir" constants-target.c
  for pp_bound in '-1' '4294967296ULL' '18446744073709551615ULL' '18446744073709551616ULL'; do
    printf 'char constants_bad_extent[%s];\n' "$pp_bound" > constants-bad-extent.c
    if "$HCC1" --target "$pp_target" -o constants-bad-extent.hccir constants-bad-extent.c 2> constants-bad-extent.err; then
      echo "unsupported array extent accepted: $pp_bound ($pp_target)" >&2
      exit 1
    fi
    pp_diagnostic='array extent exceeds supported layout range'
    if test "$pp_bound" = '-1'; then pp_diagnostic='negative array extent'; fi
    if test "$pp_bound" = '18446744073709551616ULL'; then pp_diagnostic='integer literal exceeds supported 64-bit range'; fi
    pp_contract_contains "$pp_diagnostic" constants-bad-extent.err
  done
  printf '%s\n' 'long long constants_bad_size[1073741824];' > constants-bad-size.c
  if "$HCC1" --target "$pp_target" -o constants-bad-size.hccir constants-bad-size.c 2> constants-bad-size.err; then
    echo "overflowing array size accepted ($pp_target)" >&2
    exit 1
  fi
  pp_contract_contains 'array size exceeds supported layout range' constants-bad-size.err
done
