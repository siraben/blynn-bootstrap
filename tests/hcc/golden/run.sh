#!/bin/sh
set -eu

HCPP=${HCPP:-hcpp}
HCC1=${HCC1:-hcc1}
HCC_M1=${HCC_M1:-hcc-m1}
TEST_DIR=${1:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}
WORK_DIR=${WORK_DIR:-}

if test -z "$WORK_DIR"; then
  WORK_DIR=$(mktemp -d)
  trap 'rm -rf "$WORK_DIR"' EXIT INT TERM
fi

mkdir -p "$WORK_DIR"

compare() {
  label=$1
  expected=$2
  actual=$3
  if ! diff -u "$expected" "$actual"; then
    printf 'hcc-golden: %s output differed\n' "$label" >&2
    exit 1
  fi
  printf 'hcc-golden: %s matched\n' "$label"
}

"$HCPP" "$TEST_DIR/inputs/preprocess.c" > "$WORK_DIR/preprocess.i.raw"
sed 's/[[:space:]]*$//' "$WORK_DIR/preprocess.i.raw" > "$WORK_DIR/preprocess.i"
compare hcpp "$TEST_DIR/expected/preprocess.i" "$WORK_DIR/preprocess.i"

"$HCC1" --target amd64 --m1-ir -o "$WORK_DIR/return7.hccir" "$TEST_DIR/inputs/return7.i"
compare "hcc1 --m1-ir" "$TEST_DIR/expected/return7.hccir" "$WORK_DIR/return7.hccir"

"$HCC_M1" --target amd64 "$TEST_DIR/inputs/return7.hccir" "$WORK_DIR/return7.M1.raw"
sed '${/^$/d;}' "$WORK_DIR/return7.M1.raw" > "$WORK_DIR/return7.M1"
compare hcc-m1 "$TEST_DIR/expected/return7.M1" "$WORK_DIR/return7.M1"

printf 'hcc-golden: all phase boundary golden tests passed\n'
