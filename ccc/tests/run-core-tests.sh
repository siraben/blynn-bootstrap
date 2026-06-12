#!/bin/sh
# Seed smoke tests: the shrunken mlc-interp-seed interprets only the
# lambda-ladder dialect (what core-lambda.ml and parenthetical.ml use),
# so its fixtures are the Lambda-0/Lambda-1 ones, pinned to known
# outputs (stdout+stderr+exit status).
#   nix develop -c sh ccc/tests/run-core-tests.sh
set -u
cd "$(dirname "$0")/../.."

BUILD=ccc/build
mkdir -p "$BUILD"
gcc -O2 -Wall -Wextra -o "$BUILD/mlc-interp" ccc/seed/mlc-interp-seed.c || exit 1

fail=0

check() { # check dir name want
  dir=$1; name=$2; want=$3
  got=$("$BUILD/mlc-interp" "ccc/tests/$dir/$name.ml" 2>&1; echo "exit=$?")
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: got '$got', want '$want'"
    fail=1
  fi
}

check lambda arith "14
20
14
2
-42
1
0
7
2
3
exit=0"
check lambda bytesio "ABCDEFGHIJKLMNOPQRSTUVWXYZABCD
DCBAZYXWVUTSRQPONMLKJIHGFEDCBA
exit=0"
check lambda closures "5
42
15
123
42
60
101
201
exit=0"
check lambda errs "hello from the data section
escapes: \"quoted\\\" and a tab	here
ok
exit=3"
check lambda recursion "300000
6765
exit=0"
check lambda1 arrays "285
10
2 3 5 7 11 13 17 19 23 29 
exit=0"
check lambda1 curried "321
4021
44
81
42
65536
21
42
9
exit=0"
check lambda1 sort "before: 70 10 1 85 16 7 80 22 
after:  1 7 10 16 22 70 80 85 
exit=0"
check lambda1 strings "hello, lambda-1
string literals are values
HELLO, LAMBDA-1
5
exit=0"
check lambda1 words "data
lambda
rung
two
17
exit=0"

# echo: round-trip a non-trivial file (the seed's own source) byte-exactly;
# the loop must be tail-call safe for large inputs
out=$("$BUILD/mlc-interp" ccc/tests/core/echo.ml <ccc/seed/mlc-interp-seed.c | cmp -s - ccc/seed/mlc-interp-seed.c && echo same)
if [ "$out" = "same" ]; then echo "ok   echo"; else echo "FAIL echo"; fail=1; fi

if [ "$fail" = 0 ]; then echo "all core tests passed"; else exit 1; fi
