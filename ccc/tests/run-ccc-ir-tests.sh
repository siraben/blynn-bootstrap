#!/bin/sh
# HCCIR parity: ccc-cc1 output must byte-equal `hcc1 --m1-ir` on the
# preprocessed corpus. Usage: sh ccc/tests/run-ccc-ir-tests.sh [--vm]
set -u
cd "$(dirname "$0")/../.."

BUILD=ccc/build
HCPP=$BUILD/hcc-ref/bin/hcpp
HCC1=$BUILD/hcc-ref/bin/hcc1
mkdir -p "$BUILD/ccc"

PARTS=$(ls ccc/cc/[0-9]*.ml | sort)
cat ccc/tests/prelude-ocaml.ml $PARTS ccc/cc/dev/cc1main.ml > "$BUILD/ccc/ccc-cc1-host.ml"
cat $PARTS ccc/cc/dev/cc1main.ml > "$BUILD/ccc/ccc-cc1.ml"

fail=0
run_corpus() {
  runner=$1; tag=$2
  for f in tests/hcc/m1-smoke/examples/*.c tests/mescc/scaffold/*.c; do
    n=$(basename "$f" .c)
    "$HCPP" "$f" > "$BUILD/ccc/$n.i" 2>/dev/null || continue
    "$HCC1" --m1-ir -o "$BUILD/ccc/$n.ref.hccir" "$BUILD/ccc/$n.i" 2>/dev/null
    ref_st=$?
    $runner "$BUILD/ccc/$n.i" "$BUILD/ccc/$n.ccc.hccir" 2>"$BUILD/ccc/$n.err"
    ccc_st=$?
    if [ "$ref_st" != 0 ]; then
      if [ "$ccc_st" != 0 ]; then echo "ok   $n (both reject)$tag"; else echo "FAIL $n: hcc1 rejects, ccc accepts$tag"; fail=1; fi
      continue
    fi
    if [ "$ccc_st" != 0 ]; then
      echo "FAIL $n: ccc rejects ($(head -1 "$BUILD/ccc/$n.err"))$tag"; fail=1; continue
    fi
    if cmp -s "$BUILD/ccc/$n.ref.hccir" "$BUILD/ccc/$n.ccc.hccir"; then
      echo "ok   $n$tag"
    else
      echo "FAIL $n: IR differs$tag"
      diff "$BUILD/ccc/$n.ref.hccir" "$BUILD/ccc/$n.ccc.hccir" | head -6
      fail=1
    fi
  done
}

host_runner() { ocaml "$BUILD/ccc/ccc-cc1-host.ml" "$1" "$2"; }
run_corpus host_runner ""

if [ "${1:-}" = "--vm" ]; then
  sh -c '
    set -e
    gcc -O2 -o ccc/build/mzvm ccc/vm/mzvm.c 2>/dev/null || true
    ccc/build/mlc-interp ccc/stages/02-ml0-compiler.ml ccc/stages/03-adt-compiler.ml ccc/build/ccc/03.mzs
    ccc/build/mlc-interp ccc/stages/01-parenthetical.ml ccc/build/ccc/03.mzs ccc/build/ccc/03.mzbc
    ccc/build/mzvm ccc/build/ccc/03.mzbc ccc/stages/04-pattern-compiler.ml ccc/build/ccc/04.mzs
    ccc/build/mlc-interp ccc/stages/01-parenthetical.ml ccc/build/ccc/04.mzs ccc/build/ccc/04.mzbc
    ccc/build/mzvm ccc/build/ccc/04.mzbc ccc/build/ccc/ccc-cc1.ml ccc/build/ccc/ccc-cc1.mzs
    ccc/build/mlc-interp ccc/stages/01-parenthetical.ml ccc/build/ccc/ccc-cc1.mzs ccc/build/ccc/ccc-cc1.mzbc
  ' || { echo "FAIL vm chain build"; exit 1; }
  vm_runner() { ccc/build/mzvm "$BUILD/ccc/ccc-cc1.mzbc" "$1" "$2"; }
  run_corpus vm_runner " (vm)"
fi

if [ "$fail" = 0 ]; then echo "IR parity passed"; else exit 1; fi
