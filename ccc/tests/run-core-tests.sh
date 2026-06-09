#!/bin/sh
# Core-dialect fixtures for mlc-interp-seed (and later for the staged
# compilers, which must agree on the same outputs).
#   nix develop -c sh ccc/tests/run-core-tests.sh
set -u
cd "$(dirname "$0")/../.."

BUILD=ccc/build
mkdir -p "$BUILD"
gcc -O2 -Wall -Wextra -o "$BUILD/mlc-interp" ccc/seed/mlc-interp-seed.c || exit 1

fail=0

check() {
  name=$1; want_out=$2; stdin_file=$3
  if [ "$stdin_file" = "-" ]; then
    out=$("$BUILD/mlc-interp" "ccc/tests/core/$name.ml" </dev/null)
  else
    out=$("$BUILD/mlc-interp" "ccc/tests/core/$name.ml" <"$stdin_file")
  fi
  status=$?
  if [ "$status" != 0 ]; then
    echo "FAIL $name: exit $status"
    fail=1
  elif [ "$out" != "$want_out" ]; then
    echo "FAIL $name: stdout '$out', want '$want_out'"
    fail=1
  else
    echo "ok   $name"
  fi
}

check hello "hello, core" -
check fib "6765
1
1
42" -
check sieve "168" -
check tuples "0k" -

# echo: round-trip a non-trivial file (its own source)
out=$("$BUILD/mlc-interp" ccc/tests/core/echo.ml <ccc/seed/mlc-interp-seed.c | cmp -s - ccc/seed/mlc-interp-seed.c && echo same)
if [ "$out" = "same" ]; then echo "ok   echo"; else echo "FAIL echo"; fail=1; fi

if [ "$fail" = 0 ]; then echo "all core tests passed"; else exit 1; fi
