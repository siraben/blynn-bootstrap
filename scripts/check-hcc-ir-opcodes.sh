#!/bin/sh
set -eu

root=${1:-.}

if test -f "$root/hcc/src/Hcc/M1Ir.hs"; then
  hcc_dir=$root/hcc
else
  hcc_dir=$root
fi

awk_script=${HCC_OPCODE_CHECK_AWK:-}
if test -z "$awk_script"; then
  script_dir=${0%/*}
  if test -f "$script_dir/../tests/hcc/check-ir-opcodes.awk"; then
    awk_script=$script_dir/../tests/hcc/check-ir-opcodes.awk
  elif test -f "$root/tests/hcc/check-ir-opcodes.awk"; then
    awk_script=$root/tests/hcc/check-ir-opcodes.awk
  else
    echo "check-hcc-ir-opcodes: cannot find tests/hcc/check-ir-opcodes.awk" >&2
    exit 1
  fi
fi

awk -f "$awk_script" "$hcc_dir/src/Hcc/M1Ir.hs" "$hcc_dir/cbits/hcc_m1.c"
