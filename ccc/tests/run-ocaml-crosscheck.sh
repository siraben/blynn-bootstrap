#!/bin/sh
# Cross-check: every core-dialect fixture must behave identically under
# mlc-interp-seed and under a real OCaml with the compat prelude. This
# pins the bootstrap dialect as a genuine OCaml subset.
#   nix shell nixpkgs#ocaml -c sh ccc/tests/run-ocaml-crosscheck.sh
set -u
cd "$(dirname "$0")/../.."

BUILD=ccc/build
mkdir -p "$BUILD/xcheck"
fail=0

for f in ccc/tests/core/*.ml; do
  name=$(basename "$f" .ml)
  cat ccc/tests/prelude-ocaml.ml "$f" > "$BUILD/xcheck/$name.ml"
  case "$name" in
    echo) stdin=ccc/tests/core/echo.ml ;;
    *)    stdin=/dev/null ;;
  esac
  want=$("$BUILD/mlc-interp" "$f" <"$stdin"; echo "exit=$?")
  got=$(ocaml "$BUILD/xcheck/$name.ml" <"$stdin" 2>"$BUILD/xcheck/$name.err"; echo "exit=$?")
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

if [ "$fail" = 0 ]; then echo "ocaml cross-check passed"; else exit 1; fi
