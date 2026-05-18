{
  runCommand,
  mesccTools,
  stage0Src,
  mzvmSeedM2,
  cccByteCommitted,
  tccM1CccSeed,
  testsRoot,
}:

runCommand "tcc-bin-ccc-seed" {
  nativeBuildInputs = [ mesccTools ];
} ''
  build_and_run() {
    src="$1"
    expected="$2"
    name="$3"

    ${mzvmSeedM2}/bin/mzvm-seed ${cccByteCommitted}/share/ccc/ccc.byte < "$src" > "$name.M1"
    M1 --architecture amd64 --little-endian \
      -f ${stage0Src}/M2libc/amd64/amd64_defs.M1 \
      -f "$name.M1" \
      --output "$name.hex2"
    printf ':ELF_end\n' > "$name-end.hex2"
    hex2 --architecture amd64 --little-endian --base-address 0x00600000 \
      --file ${stage0Src}/M2libc/amd64/ELF-amd64.hex2 \
      --file "$name.hex2" \
      --file "$name-end.hex2" \
      --output "$name"
    chmod 555 "$name"
    set +e
    "./$name"
    actual="$?"
    set -e
    test "$actual" = "$expected"
    install -Dm644 "$name.M1" "$out/share/ccc/scaffold/$name.M1"
    install -Dm644 "$name.hex2" "$out/share/ccc/scaffold/$name.hex2"
  }

  cp ${tccM1CccSeed}/share/ccc/tcc.M1 tcc.M1
  M1 --architecture amd64 --little-endian \
    -f ${stage0Src}/M2libc/amd64/amd64_defs.M1 \
    -f tcc.M1 \
    --output tcc.hex2
  printf ':ELF_end\n' > tcc-end.hex2
  hex2 --architecture amd64 --little-endian --base-address 0x00600000 \
    --file ${stage0Src}/M2libc/amd64/ELF-amd64.hex2 \
    --file tcc.hex2 \
    --file tcc-end.hex2 \
    --output tcc
  chmod 555 tcc
  ./tcc
  install -Dm555 tcc "$out/bin/tcc"
  install -Dm644 tcc.M1 "$out/share/ccc/tcc.M1"
  install -Dm644 tcc.hex2 "$out/share/ccc/tcc.hex2"

  build_and_run ${testsRoot}/mescc/scaffold/01-return-0.c 0 01-return-0
  build_and_run ${testsRoot}/mescc/scaffold/02-return-1.c 1 02-return-1
  build_and_run ${testsRoot}/mescc/scaffold/03-call.c 0 03-call
  build_and_run ${testsRoot}/mescc/scaffold/04-call-0.c 0 04-call-0
  build_and_run ${testsRoot}/mescc/scaffold/05-call-1.c 1 05-call-1
  build_and_run ${testsRoot}/mescc/scaffold/06-call-2.c 0 06-call-2
  build_and_run ${testsRoot}/mescc/scaffold/06-call-not-1.c 0 06-call-not-1
  build_and_run ${testsRoot}/mescc/scaffold/06-not-call-1.c 0 06-not-call-1
  build_and_run ${testsRoot}/mescc/scaffold/06-return-void.c 0 06-return-void
  build_and_run ${testsRoot}/mescc/scaffold/08-assign.c 0 08-assign
  build_and_run ${testsRoot}/mescc/scaffold/08-assign-negative.c 0 08-assign-negative
  build_and_run ${testsRoot}/mescc/scaffold/10-if-0.c 0 10-if-0
  build_and_run ${testsRoot}/mescc/scaffold/11-if-1.c 0 11-if-1
  build_and_run ${testsRoot}/mescc/scaffold/12-if-eq.c 0 12-if-eq
  build_and_run ${testsRoot}/mescc/scaffold/13-if-neq.c 0 13-if-neq
  build_and_run ${testsRoot}/mescc/scaffold/14-if-goto.c 0 14-if-goto
  build_and_run ${testsRoot}/mescc/scaffold/15-if-not-f.c 0 15-if-not-f
  build_and_run ${testsRoot}/mescc/scaffold/16-cast.c 0 16-cast
  build_and_run ${testsRoot}/mescc/scaffold/16-if-t.c 0 16-if-t
  build_and_run ${testsRoot}/mescc/scaffold/17-compare-char.c 0 17-compare-char
  build_and_run ${testsRoot}/mescc/scaffold/17-compare-assign.c 0 17-compare-assign
  build_and_run ${testsRoot}/mescc/scaffold/17-compare-call.c 0 17-compare-call
  build_and_run ${testsRoot}/mescc/scaffold/17-compare-ge.c 0 17-compare-ge
  build_and_run ${testsRoot}/mescc/scaffold/17-compare-gt.c 0 17-compare-gt
  build_and_run ${testsRoot}/mescc/scaffold/17-compare-le.c 0 17-compare-le
  build_and_run ${testsRoot}/mescc/scaffold/17-compare-lt.c 0 17-compare-lt
  build_and_run ${testsRoot}/mescc/scaffold/17-compare-and.c 0 17-compare-and
  build_and_run ${testsRoot}/mescc/scaffold/17-compare-or.c 0 17-compare-or
  build_and_run ${testsRoot}/mescc/scaffold/17-compare-rotated.c 0 17-compare-rotated
  build_and_run ${testsRoot}/mescc/scaffold/18-assign-shadow.c 0 18-assign-shadow
  build_and_run ${testsRoot}/mescc/scaffold/20-while.c 0 20-while
  build_and_run ${testsRoot}/mescc/scaffold/21-char-array-simple.c 0 21-char-array-simple
  build_and_run ${testsRoot}/mescc/scaffold/21-char-array.c 0 21-char-array
  build_and_run ${testsRoot}/mescc/scaffold/22-while-char-array.c 0 22-while-char-array
  build_and_run ${testsRoot}/mescc/scaffold/30-exit-0.c 0 30-exit-0
  build_and_run ${testsRoot}/mescc/scaffold/30-exit-42.c 42 30-exit-42
  build_and_run ${testsRoot}/mescc/scaffold/33-and-or.c 0 33-and-or
  build_and_run ${testsRoot}/mescc/scaffold/34-pre-post.c 0 34-pre-post
  build_and_run ${testsRoot}/mescc/scaffold/36-compare-arithmetic.c 0 36-compare-arithmetic
  build_and_run ${testsRoot}/mescc/scaffold/36-compare-arithmetic-negative.c 0 36-compare-arithmetic-negative
  build_and_run ${testsRoot}/mescc/scaffold/37-compare-assign.c 0 37-compare-assign
  build_and_run ${testsRoot}/mescc/scaffold/40-if-else.c 0 40-if-else
  build_and_run ${testsRoot}/mescc/scaffold/42-goto-label.c 0 42-goto-label
  build_and_run ${testsRoot}/mescc/scaffold/45-void-call.c 0 45-void-call
  build_and_run ${testsRoot}/mescc/scaffold/70-function-modulo.c 0 70-function-modulo
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/ret13.c 13 hcc-ret13
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/short-circuit.c 42 hcc-short-circuit
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/call-arg-immediate.c 42 hcc-call-arg-immediate
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/signed-char-cast.c 0 hcc-signed-char-cast
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/return-coercion.c 0 hcc-return-coercion
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/wide-integer-types.c 0 hcc-wide-integer-types
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/scoped-typedef-enum.c 0 hcc-scoped-typedef-enum
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/case-cmp-ternary.c 0 hcc-case-cmp-ternary
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/address-written-scalar.c 0 hcc-address-written-scalar
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/escaped-string-magic.c 0 hcc-escaped-string-magic
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/local-aggregate.c 3 hcc-local-aggregate
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/function-pointer-call-type.c 0 hcc-function-pointer-call-type
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/dynamic-aggregate.c 0 hcc-dynamic-aggregate
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/conditional-aggregate-copy.c 0 hcc-conditional-aggregate-copy
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/archive-header-layout.c 0 hcc-archive-header-layout
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/pointer-to-pointer-callback.c 0 hcc-pointer-to-pointer-callback
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/bootstrap-qsort-pointer.c 0 hcc-bootstrap-qsort-pointer
  build_and_run ${testsRoot}/hcc/m1-smoke/examples/sizeof-member-array-bound.c 0 hcc-sizeof-member-array-bound
  build_and_run ${testsRoot}/hcc/scalar-immediate-smoke.c 0 hcc-scalar-immediate-smoke
''
