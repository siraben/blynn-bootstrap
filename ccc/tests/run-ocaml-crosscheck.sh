#!/bin/sh
# Cross-check: the bootstrap dialects are genuine OCaml subsets.
#  - lambda/lambda1 fixtures must behave identically under mlc-interp-seed
#    and under a real OCaml with the compat prelude (pins Lambda-0/Lambda-1
#    as OCaml subsets)
#  - ML0 core fixtures must behave identically as chain-compiled bytecode
#    (the mzvm artifacts left by run-stage-tests.sh) and under OCaml (pins
#    ML0); the shrunken interp no longer runs ML0
# Run after run-stage-tests.sh:
#   nix shell nixpkgs#ocaml -c sh ccc/tests/run-ocaml-crosscheck.sh
set -u
cd "$(dirname "$0")/../.."

BUILD=ccc/build
mkdir -p "$BUILD/xcheck"
fail=0

[ -x "$BUILD/mlc-interp" ] && [ -x "$BUILD/mzvm" ] || {
  echo "missing $BUILD/mlc-interp or $BUILD/mzvm; run ccc/tests/run-stage-tests.sh first" >&2
  exit 1
}

for f in ccc/tests/lambda/*.ml ccc/tests/lambda1/*.ml; do
  name=$(basename "$f" .ml)
  cat ccc/tests/prelude-ocaml.ml "$f" > "$BUILD/xcheck/$name.ml"
  want=$("$BUILD/mlc-interp" "$f" 2>/dev/null; echo "exit=$?")
  got=$(ocaml "$BUILD/xcheck/$name.ml" 2>"$BUILD/xcheck/$name.err"; echo "exit=$?")
  if [ "$want" = "$got" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    echo "  interp: $want"
    echo "  ocaml:  $got"
    sed 's/^/  | /' "$BUILD/xcheck/$name.err" | head -5
    fail=1
  fi
done

for f in ccc/tests/core/*.ml; do
  name=$(basename "$f" .ml)
  if [ ! -f "$BUILD/stage/$name.mzbc" ]; then
    echo "FAIL $name: missing $BUILD/stage/$name.mzbc (run run-stage-tests.sh first)"
    fail=1
    continue
  fi
  cat ccc/tests/prelude-ocaml.ml "$f" > "$BUILD/xcheck/$name.ml"
  case "$name" in
    echo) stdin=ccc/tests/core/echo.ml ;;
    *)    stdin=/dev/null ;;
  esac
  want=$("$BUILD/mzvm" "$BUILD/stage/$name.mzbc" <"$stdin"; echo "exit=$?")
  got=$(ocaml "$BUILD/xcheck/$name.ml" <"$stdin" 2>"$BUILD/xcheck/$name.err"; echo "exit=$?")
  if [ "$want" = "$got" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    echo "  chain:  $want"
    echo "  ocaml:  $got"
    sed 's/^/  | /' "$BUILD/xcheck/$name.err" | head -5
    fail=1
  fi
done

# the promoted compiler must emit byte-identical assembly whether it runs
# on the chain (VM) or under host OCaml — this pins evaluation-order
# equivalence of the dialect, not just fixture behavior
if [ -f "$BUILD/ccc/04.mzbc" ] && [ -f "$BUILD/ccc/ccc-cc1.ml" ]; then
  cat ccc/tests/prelude-ocaml.ml ccc/stages/pattern-compiler.ml > "$BUILD/xcheck/04.ml"
  ocaml "$BUILD/xcheck/04.ml" "$BUILD/ccc/ccc-cc1.ml" "$BUILD/xcheck/cc1.host.mzs"
  ccc/build/mzvm "$BUILD/ccc/04.mzbc" "$BUILD/ccc/ccc-cc1.ml" "$BUILD/xcheck/cc1.vm.mzs"
  if cmp -s "$BUILD/xcheck/cc1.host.mzs" "$BUILD/xcheck/cc1.vm.mzs"; then
    echo "ok   stage04 host/VM emission identical"
  else
    echo "FAIL stage04 host/VM emission differs"
    fail=1
  fi
fi

# the lambda rungs are OCaml subsets too: host-OCaml core-lambda must
# reproduce the lambda-path image of itself byte-for-byte
if [ -f "$BUILD/stage/cl-gen1.mzbc" ]; then
  cat ccc/tests/prelude-ocaml.ml ccc/stages/core-lambda.ml > "$BUILD/xcheck/cl.ml"
  ocaml "$BUILD/xcheck/cl.ml" ccc/stages/core-lambda.ml "$BUILD/xcheck/cl.host.mzbc"
  if cmp -s "$BUILD/xcheck/cl.host.mzbc" "$BUILD/stage/cl-gen1.mzbc"; then
    echo "ok   core-lambda host/chain emission identical"
  else
    echo "FAIL core-lambda host/chain emission differs"
    fail=1
  fi
fi
if [ -f "$BUILD/stage/dl-gen1.mzbc" ]; then
  cat ccc/tests/prelude-ocaml.ml ccc/stages/data-lambda.ml > "$BUILD/xcheck/dl.ml"
  ocaml "$BUILD/xcheck/dl.ml" ccc/stages/data-lambda.ml "$BUILD/xcheck/dl.host.mzbc"
  if cmp -s "$BUILD/xcheck/dl.host.mzbc" "$BUILD/stage/dl-gen1.mzbc"; then
    echo "ok   data-lambda host/chain emission identical"
  else
    echo "FAIL data-lambda host/chain emission differs"
    fail=1
  fi
fi

if [ "$fail" = 0 ]; then echo "ocaml cross-check passed"; else exit 1; fi
