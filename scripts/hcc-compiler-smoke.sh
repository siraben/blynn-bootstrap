#!/bin/sh
set -eu

HCPP=${HCPP:-hcpp}
HCC1=${HCC1:-hcc1}
HCC_M1=${HCC_M1:-hcc-m1}
TESTS_DIR=${TESTS_DIR:-tests/hcc}
LOG_PREFIX=${LOG_PREFIX:-hcc-compiler-smoke}

log() {
  printf '%s: %s\n' "$LOG_PREFIX" "$*"
}

expect_file_contains() {
  pattern=$1
  file=$2
  found=0
  while IFS= read -r line; do
    case "$line" in
      *"$pattern"*) found=1; break ;;
    esac
  done < "$file"
  if test "$found" != 1; then
    echo "$file: expected diagnostic containing: $pattern" >&2
    while IFS= read -r line; do
      printf '  %s\n' "$line" >&2
    done < "$file"
    exit 1
  fi
}

expect_hcpp_contains() {
  name=$1
  pattern=$2
  src=$3
  log "START hcpp output contains $name"
  "$HCPP" "$src" > "$name.i"
  expect_file_contains "$pattern" "$name.i"
  log "DONE  hcpp output contains $name"
}

expect_hcpp_absent() {
  name=$1
  pattern=$2
  src=$3
  log "START hcpp output absent $name"
  "$HCPP" "$src" > "$name.i"
  while IFS= read -r line; do
    case "$line" in
      *"$pattern"*)
        echo "$name.i: unexpected output containing: $pattern" >&2
        exit 1
        ;;
    esac
  done < "$name.i"
  log "DONE  hcpp output absent $name"
}

run_check_case() {
  name=$1
  src=$2
  log "START hcpp $name"
  "$HCPP" "$src" > "$name.i"
  log "DONE  hcpp $name"
  log "START hcc1 --check $name"
  "$HCC1" --check "$name.i"
  log "DONE  hcc1 --check $name"
}

run_m1_case() {
  name=$1
  src=$2
  log "START hcpp $name"
  "$HCPP" "$src" > "$name.i"
  log "DONE  hcpp $name"
  log "START hcc1 --m1-ir $name"
  "$HCC1" --m1-ir -o "$name.hccir" "$name.i"
  log "DONE  hcc1 --m1-ir $name"
  log "START hcc-m1 $name"
  "$HCC_M1" "$name.hccir" "$name.M1"
  log "DONE  hcc-m1 $name"
}

write_trailing_space_continuation_case() {
  dst=$1
  {
    printf '#define CONTINUED_WITH_TRAILING_SPACE(x) \\   \n'
    printf '  ((x) + 1)\n'
    printf 'int continued = CONTINUED_WITH_TRAILING_SPACE(2);\n'
  } > "$dst"
}

write_macro_diagnostic_cases() {
  printf '#define BAD_PARAMETER(1arg) 0\n' > invalid-macro-parameter.c
  printf '#define BAD_VARIADIC_ORDER(first, ..., last) first\n' > variadic-macro-parameter-order.c
}

expect_hcc1_fail() {
  name=$1
  pattern=$2
  src=$3
  log "START hcpp $name"
  "$HCPP" "$src" > "$name.i"
  log "DONE  hcpp $name"
  log "START expect hcc1 failure $name"
  set +e
  "$HCC1" --m1-ir -o "$name.hccir" "$name.i" 2> "$name.err"
  code=$?
  set -e
  if test "$code" = 0; then
    echo "$name: expected hcc1 failure" >&2
    exit 1
  fi
  expect_file_contains "$pattern" "$name.err"
  log "DONE  expect hcc1 failure $name"
}

expect_hcpp_fail() {
  name=$1
  pattern=$2
  src=$3
  log "START expect hcpp failure $name"
  set +e
  "$HCPP" "$src" > "$name.i" 2> "$name.err"
  code=$?
  set -e
  if test "$code" = 0; then
    echo "$name: expected hcpp failure" >&2
    exit 1
  fi
  expect_file_contains "$pattern" "$name.err"
  log "DONE  expect hcpp failure $name"
}

write_trailing_space_continuation_case pp-smoke-trailing-space.c
write_macro_diagnostic_cases
run_check_case pp-smoke "$TESTS_DIR/pp-smoke.c"
run_check_case pp-smoke-trailing-space pp-smoke-trailing-space.c
run_check_case parse-smoke "$TESTS_DIR/parse-smoke.c"

run_m1_case parse-smoke "$TESTS_DIR/parse-smoke.c"
run_m1_case scoped-typedef-enum "$TESTS_DIR/m1-smoke/examples/scoped-typedef-enum.c"
run_m1_case wide-integer-types "$TESTS_DIR/m1-smoke/examples/wide-integer-types.c"
run_m1_case return-coercion "$TESTS_DIR/m1-smoke/examples/return-coercion.c"
run_m1_case function-pointer-call-type "$TESTS_DIR/m1-smoke/examples/function-pointer-call-type.c"
run_m1_case bootstrap-qsort-pointer "$TESTS_DIR/m1-smoke/examples/bootstrap-qsort-pointer.c"
run_m1_case for-decl-scope "$TESTS_DIR/m1-smoke/examples/for-decl-scope.c"
run_m1_case typedef-shadow "$TESTS_DIR/m1-smoke/examples/typedef-shadow.c"
run_m1_case asm-nop "$TESTS_DIR/m1-smoke/examples/asm-nop.c"
run_m1_case scalar-immediate-smoke "$TESTS_DIR/scalar-immediate-smoke.c"
run_m1_case float-literals "$TESTS_DIR/m1-smoke/examples/float-literals.c"
run_m1_case literal-acceptance "$TESTS_DIR/m1-smoke/examples/literal-acceptance.c"

expect_hcpp_contains pp-macro-include "pp_included_value" "$TESTS_DIR/pp-smoke.c"
expect_hcpp_contains pp-paste-left-raw "paste_left_raw = Ab" "$TESTS_DIR/pp-smoke.c"
expect_hcpp_contains pp-paste-pp-number "paste_pp_number = ATTR_PRINTF_1_0" "$TESTS_DIR/pp-smoke.c"
expect_hcpp_contains pp-empty-arg "empty_arg = 0" "$TESTS_DIR/pp-smoke.c"
expect_hcpp_contains pp-if-mod-ternary "pp_if_mod = 1" "$TESTS_DIR/pp-smoke.c"
expect_hcpp_contains pp-mutual-object-cycle "int HCC_CYCLE_A" "$TESTS_DIR/pp-smoke.c"
expect_hcpp_contains pp-standard-variadic "standard_variadic = 1 + 2" "$TESTS_DIR/pp-smoke.c"
expect_hcpp_contains pp-named-variadic "named_variadic = 3 + 4" "$TESTS_DIR/pp-smoke.c"
expect_hcpp_absent pp-nested-invocation-hide "NESTED_JOIN" "$TESTS_DIR/pp-smoke.c"
expect_hcpp_contains pp-self-member "self_member_rescan = object . SELF_MEMBER" "$TESTS_DIR/pp-smoke.c"
expect_hcpp_absent pp-no-double-self-member "state -> state -> text_section" "$TESTS_DIR/pp-smoke.c"
expect_hcpp_contains pp-short-circuit "short_circuit_and" "$TESTS_DIR/pp-short-circuit.c"
expect_hcpp_absent pp-short-circuit-dead "dead_and" "$TESTS_DIR/pp-short-circuit.c"

expect_hcc1_fail unknown-identifier "unknown identifier: missing_global" "$TESTS_DIR/diagnostics/unknown-identifier.c"
expect_hcc1_fail unknown-global-initializer "unknown constant: missing_global" "$TESTS_DIR/diagnostics/unknown-global-initializer.c"
expect_hcc1_fail unsupported-inline-asm "unsupported inline assembly" "$TESTS_DIR/diagnostics/unsupported-inline-asm.c"
expect_hcc1_fail integer-literal-overflow "integer literal is too large" "$TESTS_DIR/diagnostics/integer-literal-overflow.c"
expect_hcpp_fail multi-char-constant "invalid character constant" "$TESTS_DIR/diagnostics/multi-char-constant.c"
expect_hcpp_fail invalid-octal-constant "invalid digit in octal constant" "$TESTS_DIR/diagnostics/invalid-octal-constant.c"
expect_hcpp_fail invalid-macro-parameter "bad macro parameter: 1arg" invalid-macro-parameter.c
expect_hcpp_fail variadic-macro-parameter-order "bad variadic macro parameter" variadic-macro-parameter-order.c

log "all compiler smoke checks passed"
