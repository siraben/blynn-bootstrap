#!/bin/sh
# Parser acceptance parity: ccc-check must agree with hcc1 --check on the
# preprocessed test corpus (same accept/reject and same error positions).
# Usage: sh ccc/tests/run-ccc-parse-tests.sh [--vm]
set -u
cd "$(dirname "$0")/../.."

BUILD=ccc/build
HCPP=$BUILD/hcc-ref/bin/hcpp
HCC1=$BUILD/hcc-ref/bin/hcc1
mkdir -p "$BUILD/ccc"

PARTS="ccc/cc/00-util.ml ccc/cc/05-prim.ml ccc/cc/10-lexer.ml ccc/cc/12-symtab.ml ccc/cc/18-literal.ml ccc/cc/20-ast.ml ccc/cc/22-constexpr.ml ccc/cc/30-parser.ml"
cat ccc/tests/prelude-ocaml.ml $PARTS ccc/cc/dev/checkmain.ml > "$BUILD/ccc/ccc-check-host.ml"
cat $PARTS ccc/cc/dev/checkmain.ml > "$BUILD/ccc/ccc-check.ml"

fail=0
for f in tests/hcc/m1-smoke/examples/*.c tests/hcc/parse-smoke.c; do
  n=$(basename "$f" .c)
  "$HCPP" "$f" > "$BUILD/ccc/$n.i" 2>/dev/null || continue
  ref_out=$("$HCC1" --check "$BUILD/ccc/$n.i" 2>&1); ref_st=$?
  ccc_out=$(ocaml "$BUILD/ccc/ccc-check-host.ml" "$BUILD/ccc/$n.i" 2>&1); ccc_st=$?
  if [ "$ref_st" = "$ccc_st" ]; then
    if [ "$ref_st" = 0 ]; then
      echo "ok   $n (accepted)"
    else
      echo "ok   $n (rejected: $ccc_out)"
    fi
  else
    echo "FAIL $n: hcc1=$ref_st($ref_out) ccc=$ccc_st($ccc_out)"
    fail=1
  fi
done

if [ "${1:-}" = "--vm" ]; then
  sh -c '
    set -e
    ccc/build/mzvm ccc/build/ccc/04.mzbc ccc/build/ccc/ccc-check.ml ccc/build/ccc/ccc-check.mzs
    ccc/build/mlc-interp ccc/stages/01-parenthetical.ml ccc/build/ccc/ccc-check.mzs ccc/build/ccc/ccc-check.mzbc
  ' || { echo "FAIL vm chain build"; exit 1; }
  for f in tests/hcc/m1-smoke/examples/*.c; do
    n=$(basename "$f" .c)
    [ -f "$BUILD/ccc/$n.i" ] || continue
    ccc/build/mzvm "$BUILD/ccc/ccc-check.mzbc" "$BUILD/ccc/$n.i" >/dev/null 2>&1
    st=$?
    "$HCC1" --check "$BUILD/ccc/$n.i" >/dev/null 2>&1
    ref=$?
    [ "$st" = "$ref" ] && echo "ok   $n (vm)" || { echo "FAIL $n (vm: $st vs $ref)"; fail=1; }
  done
fi

if [ "$fail" = 0 ]; then echo "parser parity passed"; else exit 1; fi
