#!/bin/sh
# Preprocessor parity: ccpp must reproduce hcpp's output byte-for-byte
# (stdout, stderr shape and exit codes) on the corpus.
# Usage: sh ccc/tests/run-ccpp-tests.sh [--vm]
set -u
cd "$(dirname "$0")/../.."

BUILD=ccc/build
HCPP=$BUILD/hcc-ref/bin/hcpp
mkdir -p "$BUILD/ccc"

CPP_PARTS="ccc/cc/util.ml ccc/cc/prim.ml ccc/cc/lexer.ml ccc/cc/symtab.ml ccc/cc/literal.ml ccc/cc/ast.ml ccc/cc/constexpr.ml ccc/cc/preproc.ml ccc/cc/include.ml"
cat ccc/tests/prelude-ocaml.ml $CPP_PARTS ccc/cc/dev/cppmain.ml > "$BUILD/ccc/ccpp-host.ml"
cat $CPP_PARTS ccc/cc/dev/cppmain.ml > "$BUILD/ccc/ccpp.ml"

fail=0
run_corpus() {
  runner=$1; tag=$2
  for f in tests/hcc/m1-smoke/examples/*.c tests/mescc/scaffold/*.c tests/hcc/pp-smoke.c; do
    n=$(basename "$f" .c)
    "$HCPP" "$f" > "$BUILD/ccc/$n.pp.ref" 2>/dev/null; ref_st=$?
    $runner "$f" > "$BUILD/ccc/$n.pp.ccc" 2>/dev/null; ccc_st=$?
    if [ "$ref_st" != "$ccc_st" ]; then
      echo "FAIL $n: exit $ref_st vs $ccc_st$tag"; fail=1
    elif [ "$ref_st" = 0 ] && ! cmp -s "$BUILD/ccc/$n.pp.ref" "$BUILD/ccc/$n.pp.ccc"; then
      echo "FAIL $n: output differs$tag"; fail=1
    else
      echo "ok   $n$tag"
    fi
  done
}

host_runner() { ocaml "$BUILD/ccc/ccpp-host.ml" "$1"; }
run_corpus host_runner ""

if [ "${1:-}" = "--vm" ]; then
  ccc/build/mzvm ccc/build/ccc/04.mzbc "$BUILD/ccc/ccpp.ml" "$BUILD/ccc/ccpp.mzs" &&
  ccc/build/mlc-interp ccc/stages/parenthetical.ml "$BUILD/ccc/ccpp.mzs" "$BUILD/ccc/ccpp.mzbc" || { echo "FAIL vm build"; exit 1; }
  vm_runner() { ccc/build/mzvm "$BUILD/ccc/ccpp.mzbc" "$1"; }
  run_corpus vm_runner " (vm)"
fi

if [ "$fail" = 0 ]; then echo "ccpp parity passed"; else exit 1; fi
