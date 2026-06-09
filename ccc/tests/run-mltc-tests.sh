#!/bin/sh
# Type-checker gate: mltc must accept every promoted ML source in the
# repository (stage compilers, fixtures, the ccc concatenations, and
# itself) and reject each file in ccc/tests/mltc-bad with exit 1.
# Usage: sh ccc/tests/run-mltc-tests.sh [--vm]
set -u
cd "$(dirname "$0")/../.."

BUILD=ccc/build
mkdir -p "$BUILD/ccc"

cat ccc/tests/prelude-ocaml.ml ccc/mlc/mltc.ml > "$BUILD/ccc/mltc-host.ml"

# regenerate the concatenations being gated
ls ccc/cc/[0-9]*.ml | sort | xargs cat > "$BUILD/ccc/gate-cc1.ml"
cat ccc/cc/dev/cc1main.ml >> "$BUILD/ccc/gate-cc1.ml"
cat ccc/cc/00-util.ml ccc/cc/05-prim.ml ccc/cc/10-lexer.ml ccc/cc/12-symtab.ml \
    ccc/cc/18-literal.ml ccc/cc/20-ast.ml ccc/cc/22-constexpr.ml \
    ccc/cc/70-preproc.ml ccc/cc/72-include.ml ccc/cc/dev/cppmain.ml > "$BUILD/ccc/gate-ccpp.ml"

GOOD="ccc/stages/01-parenthetical.ml ccc/stages/02-ml0-compiler.ml \
      ccc/stages/03-adt-compiler.ml ccc/stages/04-pattern-compiler.ml \
      $(ls ccc/tests/core/*.ml ccc/tests/adt/*.ml ccc/tests/pat/*.ml) \
      $BUILD/ccc/gate-cc1.ml $BUILD/ccc/gate-ccpp.ml ccc/mlc/mltc.ml"

fail=0
run_all() {
  runner=$1; tag=$2
  for f in $GOOD; do
    if $runner "$f" >/dev/null 2>"$BUILD/ccc/mltc.err"; then
      echo "ok   accept $(basename "$f")$tag"
    else
      echo "FAIL accept $(basename "$f"): $(head -1 "$BUILD/ccc/mltc.err")$tag"
      fail=1
    fi
  done
  for f in ccc/tests/mltc-bad/*.ml; do
    if $runner "$f" >/dev/null 2>/dev/null; then
      echo "FAIL reject $(basename "$f") (accepted)$tag"
      fail=1
    else
      echo "ok   reject $(basename "$f")$tag"
    fi
  done
}

host_runner() { ocaml "$BUILD/ccc/mltc-host.ml" "$1"; }
run_all host_runner ""

if [ "${1:-}" = "--vm" ]; then
  ccc/build/mzvm ccc/build/ccc/04.mzbc ccc/mlc/mltc.ml "$BUILD/ccc/mltc.mzs" &&
  ccc/build/mlc-interp ccc/stages/01-parenthetical.ml "$BUILD/ccc/mltc.mzs" "$BUILD/ccc/mltc.mzbc" || { echo "FAIL vm build"; exit 1; }
  vm_runner() { ccc/build/mzvm "$BUILD/ccc/mltc.mzbc" "$1"; }
  run_all vm_runner " (vm)"
fi

if [ "$fail" = 0 ]; then echo "mltc gate passed"; else exit 1; fi
