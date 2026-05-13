#!/bin/sh
set -eu

HCC1=${HCC1:-hcc1}
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TMPDIR=${TMPDIR:-/tmp}
tmp=$TMPDIR/hcc-fuzz-regressions.$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

check_no_crash()
{
  file=$1
  name=$(basename "$file")

  set +e
  timeout 5 "$HCC1" --check "$file" >"$tmp/$name.check.out" 2>"$tmp/$name.check.err"
  status=$?
  set -e
  if [ "$status" -eq 124 ] || [ "$status" -ge 128 ]; then
    echo "$name: hcc1 --check crashed or timed out with status $status" >&2
    cat "$tmp/$name.check.err" >&2
    exit 1
  fi

  set +e
  timeout 5 "$HCC1" --m1-ir -o "$tmp/$name.hccir" "$file" >"$tmp/$name.m1.out" 2>"$tmp/$name.m1.err"
  status=$?
  set -e
  if [ "$status" -eq 124 ] || [ "$status" -ge 128 ]; then
    echo "$name: hcc1 --m1-ir crashed or timed out with status $status" >&2
    cat "$tmp/$name.m1.err" >&2
    exit 1
  fi
}

for file in "$DIR"/cases/*.c; do
  check_no_crash "$file"
done
