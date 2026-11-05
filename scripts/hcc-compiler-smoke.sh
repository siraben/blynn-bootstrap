#!/bin/sh
set -eu

HCPP=${HCPP:-hcpp}
HCC1=${HCC1:-hcc1}
HCC_M1=${HCC_M1:-hcc-m1}
TESTS_DIR=${TESTS_DIR:-tests/hcc}
LOG_PREFIX=${LOG_PREFIX:-hcc-compiler-smoke}

# Only check that freshly built compiler stages work. Executable coverage lives
# in m1-smoke; the TinyCC bootstrap is the end-to-end correctness gate.
for name in pp-smoke parse-smoke; do
  printf '%s: %s\n' "$LOG_PREFIX" "$name"
  "$HCPP" "$TESTS_DIR/$name.c" > "$name.i"
  "$HCC1" --check "$name.i"
done
"$HCC1" --m1-ir -o parse-smoke.hccir parse-smoke.i
"$HCC_M1" parse-smoke.hccir parse-smoke.M1

log() {
  printf '%s: %s\n' "$LOG_PREFIX" "$*"
}

expect_file_contains() {
  pattern=$1
  file=$2
  while IFS= read -r line; do
    case "$line" in *"$pattern"*) return 0 ;; esac
  done < "$file"
  printf '%s: expected diagnostic containing: %s\n' "$file" "$pattern" >&2
  exit 1
}

. "$TESTS_DIR/target-contract.sh"
