#!/bin/sh
# Staged bootstrap checks:
#  1. every core fixture compiled by stage 02 + assembled by stage 01 must
#     behave on mzvm exactly as it does under mlc-interp-seed
#  2. stage 02 compiles stage 01; the compiled assembler must produce
#     byte-identical .mzbc output
#  3. stage 02 compiles itself; the compiled compiler must reproduce its
#     own bytecode (diverse double-compilation anchor)
#   nix develop -c sh ccc/tests/run-stage-tests.sh
set -u
cd "$(dirname "$0")/../.."

BUILD=ccc/build
S=ccc/stages
mkdir -p "$BUILD/stage"
gcc -O2 -o "$BUILD/mzvm" ccc/vm/mzvm.c || exit 1
gcc -O2 -o "$BUILD/mlc-interp" ccc/seed/mlc-interp-seed.c || exit 1

INTERP=$BUILD/mlc-interp
MZVM=$BUILD/mzvm
fail=0

compile() { # compile $1.ml -> $2.mzbc via interp-run stages
  "$INTERP" "$S/02-ml0-compiler.ml" "$1" "$BUILD/stage/$2.mzs" &&
  "$INTERP" "$S/01-parenthetical.ml" "$BUILD/stage/$2.mzs" "$BUILD/stage/$2.mzbc"
}

# 1. fixtures
for f in ccc/tests/core/*.ml; do
  name=$(basename "$f" .ml)
  case "$name" in
    echo) stdin=ccc/tests/core/echo.ml ;;
    *)    stdin=/dev/null ;;
  esac
  want=$("$INTERP" "$f" <"$stdin"; echo "exit=$?")
  if ! compile "$f" "$name"; then
    echo "FAIL $name (compile)"; fail=1; continue
  fi
  got=$("$MZVM" "$BUILD/stage/$name.mzbc" <"$stdin"; echo "exit=$?")
  if [ "$want" = "$got" ]; then
    echo "ok   $name (interp = compiled)"
  else
    echo "FAIL $name: interp '$want' vs compiled '$got'"
    fail=1
  fi
done

# 2. stage 02 compiles stage 01; compiled assembler must agree byte-for-byte
if compile "$S/01-parenthetical.ml" 01; then
  ok01=1
  for f in ccc/tests/vm/*.mzs; do
    n=$(basename "$f" .mzs)
    "$INTERP" "$S/01-parenthetical.ml" "$f" "$BUILD/stage/$n.ref.mzbc"
    "$MZVM" "$BUILD/stage/01.mzbc" "$f" "$BUILD/stage/$n.via02.mzbc"
    cmp -s "$BUILD/stage/$n.ref.mzbc" "$BUILD/stage/$n.via02.mzbc" || { echo "FAIL compiled-01 on $n"; ok01=0; }
  done
  [ "$ok01" = 1 ] && echo "ok   compiled stage 01 assembler agrees"
  [ "$ok01" = 1 ] || fail=1
else
  echo "FAIL compiling stage 01"; fail=1
fi

# 3. self-compilation fixpoint: interp-run 02 and VM-run 02 must emit the
#    same assembly for 02 itself, and again one generation later
if compile "$S/02-ml0-compiler.ml" 02gen1; then
  "$MZVM" "$BUILD/stage/02gen1.mzbc" "$S/02-ml0-compiler.ml" "$BUILD/stage/02gen2.mzs" &&
  "$INTERP" "$S/01-parenthetical.ml" "$BUILD/stage/02gen2.mzs" "$BUILD/stage/02gen2.mzbc"
  if cmp -s "$BUILD/stage/02gen1.mzbc" "$BUILD/stage/02gen2.mzbc"; then
    echo "ok   stage 02 self-compilation fixpoint"
  else
    echo "FAIL stage 02 self-compilation fixpoint"
    fail=1
  fi
else
  echo "FAIL compiling stage 02"; fail=1
fi

# 4. stage 03 (ADTs + shallow match): built by 02, must be a conservative
#    extension (byte-identical .mzs for ML0 inputs), recompile itself to a
#    fixpoint, and pass the ML1 fixtures
if compile "$S/03-adt-compiler.ml" 03gen1; then
  ok03=1
  # conservative extension on ML0 fixtures
  for f in ccc/tests/core/*.ml; do
    n=$(basename "$f" .ml)
    "$MZVM" "$BUILD/stage/03gen1.mzbc" "$f" "$BUILD/stage/$n.via03.mzs"
    cmp -s "$BUILD/stage/$n.mzs" "$BUILD/stage/$n.via03.mzs" || { echo "FAIL stage03 not conservative on $n"; ok03=0; }
  done
  # self-compilation fixpoint
  "$MZVM" "$BUILD/stage/03gen1.mzbc" "$S/03-adt-compiler.ml" "$BUILD/stage/03gen2.mzs" &&
  "$INTERP" "$S/01-parenthetical.ml" "$BUILD/stage/03gen2.mzs" "$BUILD/stage/03gen2.mzbc"
  cmp -s "$BUILD/stage/03gen1.mzbc" "$BUILD/stage/03gen2.mzbc" || { echo "FAIL stage 03 self-compilation fixpoint"; ok03=0; }
  # ML1 fixtures
  check_adt() {
    name=$1; want=$2
    "$MZVM" "$BUILD/stage/03gen1.mzbc" "ccc/tests/adt/$name.ml" "$BUILD/stage/$name.mzs" &&
    "$INTERP" "$S/01-parenthetical.ml" "$BUILD/stage/$name.mzs" "$BUILD/stage/$name.mzbc" || { echo "FAIL $name (compile)"; ok03=0; return; }
    got=$("$MZVM" "$BUILD/stage/$name.mzbc")
    if [ "$got" = "$want" ]; then echo "ok   $name (adt)"; else echo "FAIL $name: '$got'"; ok03=0; fi
  }
  check_adt eval "40"
  check_adt list "5050
100"
  check_adt classify "100
101
102
42
rgbTF"
  [ "$ok03" = 1 ] && echo "ok   stage 03 conservative + fixpoint"
  [ "$ok03" = 1 ] || fail=1
else
  echo "FAIL compiling stage 03"; fail=1
fi

# 5. stage 04 (nested patterns, list sugar, refs): built by stage 03,
#    conservative on ML0/ML1 inputs, self-fixpoint, ML2 fixtures
asm04() { # asm04 src.ml out-tag
  "$MZVM" "$BUILD/stage/04gen1.mzbc" "$1" "$BUILD/stage/$2.mzs" &&
  "$INTERP" "$S/01-parenthetical.ml" "$BUILD/stage/$2.mzs" "$BUILD/stage/$2.mzbc"
}
if "$MZVM" "$BUILD/stage/03gen1.mzbc" "$S/04-pattern-compiler.ml" "$BUILD/stage/04gen1.mzs" &&
   "$INTERP" "$S/01-parenthetical.ml" "$BUILD/stage/04gen1.mzs" "$BUILD/stage/04gen1.mzbc"; then
  ok04=1
  for f in ccc/tests/core/*.ml ccc/tests/adt/*.ml; do
    n=$(basename "$f" .ml)
    "$MZVM" "$BUILD/stage/04gen1.mzbc" "$f" "$BUILD/stage/$n.via04.mzs"
    cmp -s "$BUILD/stage/$n.mzs" "$BUILD/stage/$n.via04.mzs" || { echo "FAIL stage04 not conservative on $n"; ok04=0; }
  done
  "$MZVM" "$BUILD/stage/04gen1.mzbc" "$S/04-pattern-compiler.ml" "$BUILD/stage/04gen2.mzs" &&
  "$INTERP" "$S/01-parenthetical.ml" "$BUILD/stage/04gen2.mzs" "$BUILD/stage/04gen2.mzbc"
  cmp -s "$BUILD/stage/04gen1.mzbc" "$BUILD/stage/04gen2.mzbc" || { echo "FAIL stage 04 self-compilation fixpoint"; ok04=0; }
  check_pat() {
    name=$1; want=$2
    asm04 "ccc/tests/pat/$name.ml" "$name" || { echo "FAIL $name (compile)"; ok04=0; return; }
    got=$("$MZVM" "$BUILD/stage/$name.mzbc")
    if [ "$got" = "$want" ]; then echo "ok   $name (pat)"; else echo "FAIL $name: '$got'"; ok04=0; fi
  }
  check_pat nested "24
8
12342"
  check_pat lists "15
15
8
13"
  check_pat refs "42
9 2
55"
  check_pat options "48
79"
  [ "$ok04" = 1 ] && echo "ok   stage 04 conservative + fixpoint"
  [ "$ok04" = 1 ] || fail=1
else
  echo "FAIL compiling stage 04"; fail=1
fi

if [ "$fail" = 0 ]; then echo "all stage tests passed"; else exit 1; fi
