#!/bin/sh
# VM smoke tests: assemble each .mzs with the dev assembler and check
# exit codes / stdout. Run from the repo root, e.g.:
#   nix develop -c sh ccc/tests/run-vm-tests.sh
set -u
cd "$(dirname "$0")/../.."

BUILD=ccc/build
mkdir -p "$BUILD"
gcc -O2 -Wall -Wextra -Wno-unused-variable -o "$BUILD/mzvm" ccc/vm/mzvm.c || exit 1

fail=0

check() {
  name=$1; want_status=$2; want_out=$3; heap=$4
  python3 ccc/tools/mzbc_asm.py "ccc/tests/vm/$name.mzs" "$BUILD/$name.mzbc" || { echo "FAIL $name (assemble)"; fail=1; return; }
  out=$(MZVM_HEAP_WORDS=$heap "$BUILD/mzvm" "$BUILD/$name.mzbc")
  status=$?
  if [ "$status" != "$want_status" ]; then
    echo "FAIL $name: exit $status, want $want_status"
    fail=1
  elif [ "$out" != "$want_out" ]; then
    echo "FAIL $name: stdout '$out', want '$want_out'"
    fail=1
  else
    echo "ok   $name"
  fi
}

check print42  0  "42" 8388608
check fib      55 ""   8388608
check tailcall 42 ""   8388608
check gclist   20 ""   4096
check bytesio  0  "HI!
DATA" 8388608

if [ "$fail" = 0 ]; then echo "all VM tests passed"; else exit 1; fi
