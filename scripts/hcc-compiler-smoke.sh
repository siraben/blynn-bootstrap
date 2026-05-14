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
    exit 1
  fi
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

run_check_case pp-smoke "$TESTS_DIR/pp-smoke.c"
run_check_case parse-smoke "$TESTS_DIR/parse-smoke.c"

run_m1_case parse-smoke "$TESTS_DIR/parse-smoke.c"
run_m1_case scoped-typedef-enum "$TESTS_DIR/m1-smoke/examples/scoped-typedef-enum.c"
run_m1_case wide-integer-types "$TESTS_DIR/m1-smoke/examples/wide-integer-types.c"
run_m1_case function-pointer-call-type "$TESTS_DIR/m1-smoke/examples/function-pointer-call-type.c"
run_m1_case bootstrap-qsort-pointer "$TESTS_DIR/m1-smoke/examples/bootstrap-qsort-pointer.c"
run_m1_case scalar-immediate-smoke "$TESTS_DIR/scalar-immediate-smoke.c"
run_m1_case float-literals "$TESTS_DIR/m1-smoke/examples/float-literals.c"

expect_hcc1_fail unknown-identifier "unknown identifier: missing_global" "$TESTS_DIR/diagnostics/unknown-identifier.c"
expect_hcc1_fail unknown-global-initializer "unknown constant: missing_global" "$TESTS_DIR/diagnostics/unknown-global-initializer.c"

log "all compiler smoke checks passed"
