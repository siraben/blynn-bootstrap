{
  stageRun,
  cccSrc,
  testsRoot,
  mzvmSeedM2,
  mlcByteCommitted,
}:

stageRun {
  pname = "ccc-byte-seed";
  nativeBuildInputs = [
    mzvmSeedM2
  ];
  description = "Current ccc.ml compiled to MZBC by fixed-point mlc.byte";
  buildScript = ''
    cp ${cccSrc}/ccc.ml ccc.ml
    ${mzvmSeedM2}/bin/mzvm-seed ${mlcByteCommitted}/share/mlc/mlc.byte < ccc.ml > ccc.byte
    check_return() {
      actual="$(${mzvmSeedM2}/bin/mzvm-seed ccc.byte < "$1")"
      expected="DEFINE LOADI32_RDI 48C7C7
DEFINE LOADI32_RAX 48C7C0
DEFINE SYSCALL 0F05

:_start
	LOADI32_RDI %$2
	LOADI32_RAX %60
	SYSCALL"
      test "$actual" = "$expected"
    }
    check_return ${testsRoot}/mescc/scaffold/01-return-0.c 0
    check_return ${testsRoot}/mescc/scaffold/02-return-1.c 1
    check_return ${testsRoot}/mescc/scaffold/03-call.c 0
    check_return ${testsRoot}/mescc/scaffold/04-call-0.c 0
    check_return ${testsRoot}/mescc/scaffold/05-call-1.c 1
    check_return ${testsRoot}/mescc/scaffold/06-call-2.c 0
    check_return ${testsRoot}/mescc/scaffold/06-call-not-1.c 0
    check_return ${testsRoot}/mescc/scaffold/06-not-call-1.c 0
    check_return ${testsRoot}/mescc/scaffold/06-return-void.c 0
    check_return ${testsRoot}/mescc/scaffold/08-assign.c 0
    check_return ${testsRoot}/mescc/scaffold/08-assign-negative.c 0
    check_return ${testsRoot}/mescc/scaffold/10-if-0.c 0
    check_return ${testsRoot}/mescc/scaffold/11-if-1.c 0
    check_return ${testsRoot}/mescc/scaffold/12-if-eq.c 0
    check_return ${testsRoot}/mescc/scaffold/13-if-neq.c 0
    check_return ${testsRoot}/mescc/scaffold/14-if-goto.c 0
    check_return ${testsRoot}/mescc/scaffold/15-if-not-f.c 0
    check_return ${testsRoot}/mescc/scaffold/16-cast.c 0
    check_return ${testsRoot}/mescc/scaffold/16-if-t.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-char.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-assign.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-call.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-ge.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-gt.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-le.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-lt.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-and.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-or.c 0
    check_return ${testsRoot}/mescc/scaffold/17-compare-rotated.c 0
    check_return ${testsRoot}/mescc/scaffold/18-assign-shadow.c 0
    check_return ${testsRoot}/mescc/scaffold/20-while.c 0
    check_return ${testsRoot}/mescc/scaffold/21-char-array-simple.c 0
    check_return ${testsRoot}/mescc/scaffold/21-char-array.c 0
    check_return ${testsRoot}/mescc/scaffold/22-while-char-array.c 0
    check_return ${testsRoot}/mescc/scaffold/30-exit-0.c 0
    check_return ${testsRoot}/mescc/scaffold/30-exit-42.c 42
    check_return ${testsRoot}/mescc/scaffold/33-and-or.c 0
    check_return ${testsRoot}/mescc/scaffold/34-pre-post.c 0
    check_return ${testsRoot}/mescc/scaffold/36-compare-arithmetic.c 0
    check_return ${testsRoot}/mescc/scaffold/36-compare-arithmetic-negative.c 0
    check_return ${testsRoot}/mescc/scaffold/37-compare-assign.c 0
    check_return ${testsRoot}/mescc/scaffold/40-if-else.c 0
    check_return ${testsRoot}/mescc/scaffold/42-goto-label.c 0
    check_return ${testsRoot}/mescc/scaffold/45-void-call.c 0
    check_return ${testsRoot}/mescc/scaffold/70-function-modulo.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/ret13.c 13
    check_return ${testsRoot}/hcc/m1-smoke/examples/short-circuit.c 42
    check_return ${testsRoot}/hcc/m1-smoke/examples/call-arg-immediate.c 42
    check_return ${testsRoot}/hcc/m1-smoke/examples/signed-char-cast.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/return-coercion.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/wide-integer-types.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/scoped-typedef-enum.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/case-cmp-ternary.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/address-written-scalar.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/escaped-string-magic.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/local-aggregate.c 3
    check_return ${testsRoot}/hcc/m1-smoke/examples/function-pointer-call-type.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/dynamic-aggregate.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/conditional-aggregate-copy.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/archive-header-layout.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/pointer-to-pointer-callback.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/bootstrap-qsort-pointer.c 0
    check_return ${testsRoot}/hcc/m1-smoke/examples/sizeof-member-array-bound.c 0
    check_return ${testsRoot}/hcc/scalar-immediate-smoke.c 0
    printf 'int main(){return 42;}' > return-42.c
    check_return return-42.c 42
  '';
  installScript = ''
    install -Dm644 ccc.byte "$out/share/ccc/ccc.byte"
  '';
}
