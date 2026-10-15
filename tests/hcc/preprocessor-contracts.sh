# Sourced by compiler smoke; reuse its helpers and preprocess each fixture once.
run_check_case pp-contract-inactive "$TESTS_DIR/pp-contract-inactive.c"
expect_file_contains 'int pp_contract_inactive ;' pp-contract-inactive.i

"$HCPP" "$TESTS_DIR/pp-contract-macros.c" > pp-contract-macros.i
expect_file_contains 'pp_contract_nested = ( ( ( ( 1 ) + 1 ) ) + 1 )' pp-contract-macros.i
expect_file_contains 'pp_contract_suffix = ( ( 1 ) + 1 )' pp-contract-macros.i
expect_file_contains 'int A ;' pp-contract-macros.i
expect_file_contains 'SELF ( 1 )' pp-contract-macros.i
expect_file_contains '2 * 9 * g' pp-contract-macros.i
expect_file_contains 'one twothree four' pp-contract-macros.i

expect_hcpp_fail pp-contract-object-location ':6:1: wrong number of macro arguments' "$TESTS_DIR/pp-contract-object-location.c"
expect_hcpp_fail pp-contract-argument-location ':6:6: wrong number of macro arguments' "$TESTS_DIR/pp-contract-argument-location.c"
expect_hcpp_fail pp-contract-bad-include 'invalid active #include operand' "$TESTS_DIR/pp-contract-bad-include.c"
run_check_case pp-contract-include "$TESTS_DIR/pp-contract-include.c"
expect_file_contains 'int pp_contract_include ;' pp-contract-include.i
expect_file_contains 'int pp_contract_continued ;' pp-contract-include.i

# Both files exist: losing a separator must not silently select another header.
printf '%s\n' '#undef PP_SELECTED' '#define PP_SELECTED 13' > 'pp-contract-space name.h'
printf '%s\n' '#undef PP_SELECTED' '#define PP_SELECTED 29' > pp-contract-spacename.h
printf '%s\n' '#define PP_HEADER <pp-contract-space name.h>' '#include PP_HEADER' \
  'int pp_include_spaced = PP_SELECTED;' '#undef PP_HEADER' \
  '#define PP_HEADER <pp-contract-spacename.h>' '#include PP_HEADER' \
  'int pp_include_adjacent = PP_SELECTED;' '#undef PP_HEADER' \
  '#define PP_HEADER "pp-contract-space name.h"' '#include PP_HEADER' \
  'int pp_include_quoted = PP_SELECTED;' > pp-contract-include-spaces.c
run_check_case pp-contract-include-spaces pp-contract-include-spaces.c
expect_file_contains 'pp_include_spaced = 13' pp-contract-include-spaces.i
expect_file_contains 'pp_include_adjacent = 29' pp-contract-include-spaces.i
expect_file_contains 'pp_include_quoted = 13' pp-contract-include-spaces.i

run_check_case pp-contract-stringify "$TESTS_DIR/pp-contract-stringify.c"
expect_file_contains 'pp_adjacent = "a+b"' pp-contract-stringify.i
expect_file_contains 'pp_space = "a + b"' pp-contract-stringify.i
expect_file_contains 'pp_comment = "a +b"' pp-contract-stringify.i
expect_file_contains 'pp_expand = "a+b"' pp-contract-stringify.i
expect_file_contains 'pp_empty_object = "a +b"' pp-contract-stringify.i
expect_file_contains 'pp_empty_function = "a +b"' pp-contract-stringify.i
expect_file_contains 'pp_empty_argument = "a +b"' pp-contract-stringify.i
expect_file_contains 'pp_wrap = "a+b + c"' pp-contract-stringify.i
expect_file_contains 'pp_variadic = "a ,b, c"' pp-contract-stringify.i
expect_file_contains 'pp_escape = "\"a\\\\b\""' pp-contract-stringify.i
expect_file_contains 'pp_splice = "a+b"' pp-contract-stringify.i

run_check_case pp-contract-trailing "$TESTS_DIR/pp-contract-trailing.c"
expect_file_contains 'pp_trailing = "a b"' pp-contract-trailing.i
expect_file_contains 'pp_trailing_macro = "a b"' pp-contract-trailing.i
expect_file_contains 'pp_trailing_nested = "a b"' pp-contract-trailing.i
expect_file_contains 'pp_trailing_adjacent = "a+b"' pp-contract-trailing.i
expect_file_contains 'pp_trailing_both = "a b"' pp-contract-trailing.i
expect_file_contains 'pp_trailing_left = "a bb"' pp-contract-trailing.i
expect_file_contains 'pp_trailing_chain = "a bb"' pp-contract-trailing.i
expect_file_contains 'pp_trailing_call = "b"' pp-contract-trailing.i
expect_file_contains 'pp_empty_adjacent = "z()b"' pp-contract-trailing.i
expect_file_contains 'pp_empty_prescan = "a+ b"' pp-contract-trailing.i
expect_file_contains 'pp_empty_leading = "a+b"' pp-contract-trailing.i
expect_file_contains 'pp_leading_empty = "a+ b"' pp-contract-trailing.i
expect_file_contains 'pp_leading_paste = "a+ b"' pp-contract-trailing.i
expect_file_contains 'pp_leading_prescan = "b+ b"' pp-contract-trailing.i
run_check_case pp-contract-arithmetic "$TESTS_DIR/pp-contract-arithmetic.c"

# Two integer models; executable fixtures cover all four backend targets.
for pp_target in amd64 i386; do
  pp_model=1
  if test "$pp_target" = i386; then pp_model=0; fi
  printf '%s\n' 'enum { constants_target_enum = -1L < 1U };' \
    "_Static_assert(constants_target_enum == $pp_model, \"enum model\");" \
    "_Static_assert((-1L < 1U) == $pp_model, \"ordinary model\");" \
    '_Static_assert(4294967296ULL, "wide truth value");' \
    'enum { constants_small = 1ULL, constants_boot64 = 0xffffffffffffffffULL };' \
    '_Static_assert(~constants_small < 0, "representable enumerators have int type");' \
    '_Static_assert(constants_boot64 / 3ULL == 6148914691236517205ULL, "bootstrap uint64 enumerator");' \
    > constants-target.c
  "$HCC1" --target "$pp_target" -o "constants-target-$pp_target.hccir" constants-target.c
done

# Target-independent rejection classes, not another architecture matrix.
while IFS='|' read -r pp_source pp_diagnostic; do
  printf '%s\n' "$pp_source" > constants-invalid.c
  expect_hcc1_fail constants-invalid "$pp_diagnostic" constants-invalid.c
done <<'EOF'
char invalid[-1];|negative array extent
char invalid[4294967296ULL];|array extent exceeds supported layout range
char invalid[18446744073709551616ULL];|integer literal exceeds supported 64-bit range
long long invalid[1073741824];|array size exceeds supported layout range
double invalid = 1;|unsupported non-integer constant conversion
double invalid = (double)0;|unsupported non-integer constant conversion
int invalid = (int)3.0;|unsupported constant expression: EFloat
EOF
