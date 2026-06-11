#!/bin/sh
# Lexer parity: ccc's lexer must reproduce hcpp's token rendering
# byte-for-byte on directive-free, macro-free inputs.
# Usage: sh ccc/tests/run-ccc-lex-tests.sh [--vm]
# --vm additionally runs the staged-chain build on the VM (slower).
set -u
cd "$(dirname "$0")/../.."

BUILD=ccc/build
HCPP=$BUILD/hcc-ref/bin/hcpp
mkdir -p "$BUILD/ccc"

cat ccc/tests/prelude-ocaml.ml ccc/cc/util.ml ccc/cc/lexer.ml ccc/cc/dev/lexmain.ml > "$BUILD/ccc/ccc-lex-host.ml"
cat ccc/cc/util.ml ccc/cc/lexer.ml ccc/cc/dev/lexmain.ml > "$BUILD/ccc/ccc-lex.ml"

fail=0
files=$(grep -rL '#' tests/hcc/m1-smoke/examples/*.c)

for f in $files; do
  n=$(basename "$f" .c)
  "$HCPP" "$f" > "$BUILD/ccc/$n.tok.ref" 2>/dev/null || { echo "skip $n (hcpp rejects)"; continue; }
  ocaml "$BUILD/ccc/ccc-lex-host.ml" "$f" > "$BUILD/ccc/$n.tok.ccc" || { echo "FAIL $n (ccc-lex)"; fail=1; continue; }
  if cmp -s "$BUILD/ccc/$n.tok.ref" "$BUILD/ccc/$n.tok.ccc"; then
    echo "ok   $n"
  else
    echo "FAIL $n (diff)"; diff "$BUILD/ccc/$n.tok.ref" "$BUILD/ccc/$n.tok.ccc" | head -4
    fail=1
  fi
done

if [ "${1:-}" = "--vm" ]; then
  # build through the staged chain and re-check one file on the VM
  sh -c '
    set -e
    ccc/build/mlc-interp ccc/stages/ml0-compiler.ml ccc/stages/adt-compiler.ml ccc/build/ccc/03.mzs
    ccc/build/mlc-interp ccc/stages/parenthetical.ml ccc/build/ccc/03.mzs ccc/build/ccc/03.mzbc
    ccc/build/mzvm ccc/build/ccc/03.mzbc ccc/stages/pattern-compiler.ml ccc/build/ccc/04.mzs
    ccc/build/mlc-interp ccc/stages/parenthetical.ml ccc/build/ccc/04.mzs ccc/build/ccc/04.mzbc
    ccc/build/mzvm ccc/build/ccc/04.mzbc ccc/build/ccc/ccc-lex.ml ccc/build/ccc/ccc-lex.mzs
    ccc/build/mlc-interp ccc/stages/parenthetical.ml ccc/build/ccc/ccc-lex.mzs ccc/build/ccc/ccc-lex.mzbc
  ' || { echo "FAIL vm chain build"; exit 1; }
  for f in $files; do
    n=$(basename "$f" .c)
    [ -f "$BUILD/ccc/$n.tok.ref" ] || continue
    ccc/build/mzvm "$BUILD/ccc/ccc-lex.mzbc" "$f" > "$BUILD/ccc/$n.tok.vm" || { echo "FAIL $n (vm)"; fail=1; continue; }
    cmp -s "$BUILD/ccc/$n.tok.ref" "$BUILD/ccc/$n.tok.vm" && echo "ok   $n (vm)" || { echo "FAIL $n (vm diff)"; fail=1; }
  done
fi

if [ "$fail" = 0 ]; then echo "lexer parity passed"; else exit 1; fi
