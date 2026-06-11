#!/bin/sh
# M2-Planet seed parity tests: build mzvm and mlc-interp-seed with
# M2-Mesoplanet and check that the M2-built binaries behave byte-identically
# to the gcc builds on
#   1. the VM smoke tests (ccc/tests/vm/*.mzs),
#   2. the core-dialect fixtures (ccc/tests/core/*.ml),
#   3. the full staged bootstrap chain (02 -> 01 -> 03 -> 04 self-fixpoint),
#      with the M2 binaries doing all the interpreting/VM work.
# Run from the repo root, e.g.:
#   nix develop -c sh ccc/tests/run-m2-seed-tests.sh
# M2LIBC_PATH may be overridden via the environment. M2-Mesoplanet is taken
# from PATH if present, otherwise via
#   nix shell nixpkgs#minimal-bootstrap.mescc-tools
# Heads up: the M2-built binaries are unoptimized; the staged chain takes a
# few minutes.
set -u
cd "$(dirname "$0")/../.."

M2LIBC_PATH=${M2LIBC_PATH:-/nix/store/4f7nm8dblrdy74gmsl62b25rjrh4jcz3-stage0-posix-1.9.1-source/M2libc}
export M2LIBC_PATH

if [ ! -d "$M2LIBC_PATH" ]; then
  echo "M2LIBC_PATH does not exist: $M2LIBC_PATH" >&2
  exit 1
fi

BUILD=ccc/build/m2seed
S=ccc/stages
mkdir -p "$BUILD/stage" "$BUILD/ref"

m2_build() { # m2_build src out  (build log shown only on failure)
  log=$BUILD/$(basename "$2").build.log
  if command -v M2-Mesoplanet >/dev/null 2>&1; then
    M2-Mesoplanet --operating-system Linux --architecture amd64 -f "$1" -o "$2" >"$log" 2>&1
  else
    nix shell nixpkgs#minimal-bootstrap.mescc-tools --command \
      sh -c "M2LIBC_PATH='$M2LIBC_PATH' M2-Mesoplanet --operating-system Linux --architecture amd64 -f '$1' -o '$2'" >"$log" 2>&1
  fi
  status=$?
  [ "$status" = 0 ] || cat "$log" >&2
  return "$status"
}

echo "== building gcc references =="
gcc -O2 -Wall -Wextra -Wno-unused-variable -o "$BUILD/mzvm-gcc" ccc/vm/mzvm.c || exit 1
gcc -O2 -Wall -Wextra -o "$BUILD/mlc-interp-gcc" ccc/seed/mlc-interp-seed.c || exit 1

echo "== building with M2-Mesoplanet =="
m2_build ccc/vm/mzvm.c "$BUILD/mzvm-m2" || { echo "FAIL M2 build of mzvm.c"; exit 1; }
m2_build ccc/seed/mlc-interp-seed.c "$BUILD/mlc-interp-m2" || { echo "FAIL M2 build of mlc-interp-seed.c"; exit 1; }

fail=0

# ---- 1. VM smoke tests: M2 mzvm must match the gcc mzvm exactly ----

vm_check() { # vm_check name heap
  name=$1; heap=$2
  python3 ccc/tools/mzbc_asm.py "ccc/tests/vm/$name.mzs" "$BUILD/$name.mzbc" \
    || { echo "FAIL $name (assemble)"; fail=1; return; }
  want=$(MZVM_HEAP_WORDS=$heap "$BUILD/mzvm-gcc" "$BUILD/$name.mzbc"; echo "exit=$?")
  got=$(MZVM_HEAP_WORDS=$heap "$BUILD/mzvm-m2" "$BUILD/$name.mzbc"; echo "exit=$?")
  if [ "$want" = "$got" ]; then
    echo "ok   $name (vm m2 = gcc)"
  else
    echo "FAIL $name: gcc '$want' vs m2 '$got'"
    fail=1
  fi
}

vm_check print42  8388608
vm_check fib      8388608
vm_check tailcall 8388608
vm_check gclist   4096
vm_check bytesio  8388608

# ---- 2. core fixtures: M2 mlc-interp must match the gcc build exactly ----

core_check() { # core_check name stdin_file
  name=$1; stdin_file=$2
  want=$("$BUILD/mlc-interp-gcc" "ccc/tests/core/$name.ml" <"$stdin_file"; echo "exit=$?")
  got=$("$BUILD/mlc-interp-m2" "ccc/tests/core/$name.ml" <"$stdin_file"; echo "exit=$?")
  if [ "$want" = "$got" ]; then
    echo "ok   $name (core m2 = gcc)"
  else
    echo "FAIL $name: gcc '$want' vs m2 '$got'"
    fail=1
  fi
}

core_check hello  /dev/null
core_check fib    /dev/null
core_check sieve  /dev/null
core_check tuples /dev/null

# echo: round-trip a non-trivial file (its own source), byte-exact
"$BUILD/mlc-interp-m2" ccc/tests/core/echo.ml <ccc/seed/mlc-interp-seed.c >"$BUILD/echo.out"
if cmp -s "$BUILD/echo.out" ccc/seed/mlc-interp-seed.c; then
  echo "ok   echo (core m2 round-trip)"
else
  echo "FAIL echo (core m2 round-trip)"
  fail=1
fi

# ---- 3. staged bootstrap chain, all interp/VM work on the M2 binaries ----
# Every artifact must be byte-identical to one produced by the gcc builds.

INTERP=$BUILD/mlc-interp-m2
MZVM=$BUILD/mzvm-m2
RINTERP=$BUILD/mlc-interp-gcc

compile() { # compile $1.ml -> $BUILD/stage/$2.mzs + .mzbc via M2-run stages
  "$INTERP" "$S/ml0-compiler.ml" "$1" "$BUILD/stage/$2.mzs" &&
  "$INTERP" "$S/parenthetical.ml" "$BUILD/stage/$2.mzs" "$BUILD/stage/$2.mzbc"
}

ref_compile() { # same, with the gcc interpreter, into $BUILD/ref
  "$RINTERP" "$S/ml0-compiler.ml" "$1" "$BUILD/ref/$2.mzs" &&
  "$RINTERP" "$S/parenthetical.ml" "$BUILD/ref/$2.mzs" "$BUILD/ref/$2.mzbc"
}

cmp_ref() { # cmp_ref tag: stage/$tag.{mzs,mzbc} must equal ref/$tag.*
  cmp -s "$BUILD/stage/$1.mzs" "$BUILD/ref/$1.mzs" &&
  cmp -s "$BUILD/stage/$1.mzbc" "$BUILD/ref/$1.mzbc"
}

# 3a. fixtures: compile with M2-run 02+01, run on M2 mzvm; outputs must
#     match both the gcc-compiled artifacts and the gcc interp behavior
for f in ccc/tests/core/*.ml; do
  name=$(basename "$f" .ml)
  case "$name" in
    echo) stdin=ccc/tests/core/echo.ml ;;
    *)    stdin=/dev/null ;;
  esac
  if ! compile "$f" "$name" || ! ref_compile "$f" "$name"; then
    echo "FAIL $name (stage compile)"; fail=1; continue
  fi
  if ! cmp_ref "$name"; then
    echo "FAIL $name: M2-compiled artifacts differ from gcc-compiled"; fail=1; continue
  fi
  want=$("$RINTERP" "$f" <"$stdin"; echo "exit=$?")
  got=$("$MZVM" "$BUILD/stage/$name.mzbc" <"$stdin"; echo "exit=$?")
  if [ "$want" = "$got" ]; then
    echo "ok   $name (m2 chain = gcc interp)"
  else
    echo "FAIL $name: interp '$want' vs m2 chain '$got'"
    fail=1
  fi
done

# 3b. stage 02 compiles stage 01; the compiled assembler, run on the M2
#     VM, must reproduce the M2 interp-run assembler byte-for-byte
if compile "$S/parenthetical.ml" 01; then
  ok01=1
  for f in ccc/tests/vm/*.mzs; do
    n=$(basename "$f" .mzs)
    "$INTERP" "$S/parenthetical.ml" "$f" "$BUILD/stage/$n.ref.mzbc"
    "$MZVM" "$BUILD/stage/01.mzbc" "$f" "$BUILD/stage/$n.via02.mzbc"
    cmp -s "$BUILD/stage/$n.ref.mzbc" "$BUILD/stage/$n.via02.mzbc" || { echo "FAIL compiled-01 on $n"; ok01=0; }
  done
  [ "$ok01" = 1 ] && echo "ok   compiled stage 01 assembler agrees (m2)"
  [ "$ok01" = 1 ] || fail=1
else
  echo "FAIL compiling stage 01"; fail=1
fi

# 3c. stage 02 self-compilation fixpoint on the M2 binaries
if compile "$S/ml0-compiler.ml" 02gen1 && ref_compile "$S/ml0-compiler.ml" 02gen1 && cmp_ref 02gen1; then
  "$MZVM" "$BUILD/stage/02gen1.mzbc" "$S/ml0-compiler.ml" "$BUILD/stage/02gen2.mzs" &&
  "$INTERP" "$S/parenthetical.ml" "$BUILD/stage/02gen2.mzs" "$BUILD/stage/02gen2.mzbc"
  if cmp -s "$BUILD/stage/02gen1.mzbc" "$BUILD/stage/02gen2.mzbc"; then
    echo "ok   stage 02 self-compilation fixpoint (m2)"
  else
    echo "FAIL stage 02 self-compilation fixpoint (m2)"
    fail=1
  fi
else
  echo "FAIL compiling stage 02 (or differs from gcc)"; fail=1
fi

# 3d. stage 03: built by 02 on the M2 VM, conservative on ML0 fixtures,
#     self-fixpoint, ML1 fixtures
if compile "$S/adt-compiler.ml" 03gen1; then
  ok03=1
  for f in ccc/tests/core/*.ml; do
    n=$(basename "$f" .ml)
    "$MZVM" "$BUILD/stage/03gen1.mzbc" "$f" "$BUILD/stage/$n.via03.mzs"
    cmp -s "$BUILD/stage/$n.mzs" "$BUILD/stage/$n.via03.mzs" || { echo "FAIL stage03 not conservative on $n"; ok03=0; }
  done
  "$MZVM" "$BUILD/stage/03gen1.mzbc" "$S/adt-compiler.ml" "$BUILD/stage/03gen2.mzs" &&
  "$INTERP" "$S/parenthetical.ml" "$BUILD/stage/03gen2.mzs" "$BUILD/stage/03gen2.mzbc"
  cmp -s "$BUILD/stage/03gen1.mzbc" "$BUILD/stage/03gen2.mzbc" || { echo "FAIL stage 03 self-compilation fixpoint (m2)"; ok03=0; }
  check_adt() {
    name=$1; want=$2
    "$MZVM" "$BUILD/stage/03gen1.mzbc" "ccc/tests/adt/$name.ml" "$BUILD/stage/$name.mzs" &&
    "$INTERP" "$S/parenthetical.ml" "$BUILD/stage/$name.mzs" "$BUILD/stage/$name.mzbc" || { echo "FAIL $name (compile)"; ok03=0; return; }
    got=$("$MZVM" "$BUILD/stage/$name.mzbc")
    if [ "$got" = "$want" ]; then echo "ok   $name (adt m2)"; else echo "FAIL $name: '$got'"; ok03=0; fi
  }
  check_adt eval "40"
  check_adt list "5050
100"
  check_adt classify "100
101
102
42
rgbTF"
  [ "$ok03" = 1 ] && echo "ok   stage 03 conservative + fixpoint (m2)"
  [ "$ok03" = 1 ] || fail=1
else
  echo "FAIL compiling stage 03"; fail=1
fi

# 3e. stage 04: built by 03 on the M2 VM, conservative on ML0/ML1 inputs,
#     self-fixpoint, ML2 fixtures
asm04() { # asm04 src.ml out-tag
  "$MZVM" "$BUILD/stage/04gen1.mzbc" "$1" "$BUILD/stage/$2.mzs" &&
  "$INTERP" "$S/parenthetical.ml" "$BUILD/stage/$2.mzs" "$BUILD/stage/$2.mzbc"
}
if "$MZVM" "$BUILD/stage/03gen1.mzbc" "$S/pattern-compiler.ml" "$BUILD/stage/04gen1.mzs" &&
   "$INTERP" "$S/parenthetical.ml" "$BUILD/stage/04gen1.mzs" "$BUILD/stage/04gen1.mzbc"; then
  ok04=1
  for f in ccc/tests/core/*.ml ccc/tests/adt/*.ml; do
    n=$(basename "$f" .ml)
    "$MZVM" "$BUILD/stage/04gen1.mzbc" "$f" "$BUILD/stage/$n.via04.mzs"
    cmp -s "$BUILD/stage/$n.mzs" "$BUILD/stage/$n.via04.mzs" || { echo "FAIL stage04 not conservative on $n"; ok04=0; }
  done
  "$MZVM" "$BUILD/stage/04gen1.mzbc" "$S/pattern-compiler.ml" "$BUILD/stage/04gen2.mzs" &&
  "$INTERP" "$S/parenthetical.ml" "$BUILD/stage/04gen2.mzs" "$BUILD/stage/04gen2.mzbc"
  cmp -s "$BUILD/stage/04gen1.mzbc" "$BUILD/stage/04gen2.mzbc" || { echo "FAIL stage 04 self-compilation fixpoint (m2)"; ok04=0; }
  check_pat() {
    name=$1; want=$2
    asm04 "ccc/tests/pat/$name.ml" "$name" || { echo "FAIL $name (compile)"; ok04=0; return; }
    got=$("$MZVM" "$BUILD/stage/$name.mzbc")
    if [ "$got" = "$want" ]; then echo "ok   $name (pat m2)"; else echo "FAIL $name: '$got'"; ok04=0; fi
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
  [ "$ok04" = 1 ] && echo "ok   stage 04 conservative + fixpoint (m2)"
  [ "$ok04" = 1 ] || fail=1
else
  echo "FAIL compiling stage 04"; fail=1
fi

if [ "$fail" = 0 ]; then echo "all M2 seed tests passed"; else exit 1; fi
