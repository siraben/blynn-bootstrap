{
  stdenv,
  lib,
  ocaml,
  cccSrc,
  testsRoot,
}:

stdenv.mkDerivation {
  pname = "ccc-host-ocaml";
  version = "0-unstable-2026-05-27";

  src = cccSrc;
  nativeBuildInputs = [ ocaml ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    if grep -nE 'List\.find_opt|Option\.is_some|\( let\* \)|Buffer\.|= function|-> function|let [^=]*\?[A-Za-z_]|(^|[^A-Za-z0-9_])(when|land|lor|lxor|lsl|lsr|asr)([^A-Za-z0-9_]|$)|~[A-Za-z_][A-Za-z0-9_]*:' host/ccc_host.ml; then
      echo "ccc-host-ocaml should stay within the portable host-ML subset" >&2
      exit 1
    fi

    ocamlc host/ccc_host.ml -o ccc-host-ocaml

    check_return() {
      src="$1"
      expected_code="$2"
      actual="$(./ccc-host-ocaml < "$src")"
      expected="DEFINE LOADI32_RDI 48C7C7
DEFINE LOADI32_RAX 48C7C0
DEFINE SYSCALL 0F05

:_start
	LOADI32_RDI %$expected_code
	LOADI32_RAX %60
	SYSCALL"
      test "$actual" = "$expected"
    }

    reject_compile() {
      src="$1"
      if ./ccc-host-ocaml < "$src" > rejected.M1; then
        echo "expected ccc-host-ocaml to reject $src" >&2
        exit 1
      else
        :
      fi
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
    check_return ${testsRoot}/mescc/scaffold/80-for-loop.c 10
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
    check_return ${testsRoot}/hcc/m1-smoke/examples/do-while.c 3
    check_return ${testsRoot}/hcc/m1-smoke/examples/continue.c 42
    check_return ${testsRoot}/hcc/m1-smoke/examples/switch.c 42
    check_return ${testsRoot}/hcc/m1-smoke/examples/enum-shift.c 42
    check_return ${testsRoot}/hcc/scalar-immediate-smoke.c 0
    check_return ${testsRoot}/hcc/parse-smoke.c 0
    check_return ${testsRoot}/hcc/pp-smoke.c 0
    printf '%s\n' \
      "int accept(int ch) { return ch == 'A' || ch == 'B' || ch == 'C'; }" \
      "int main(void) {" \
      "  if (!accept('A')) return 1;" \
      "  if (!accept('B')) return 2;" \
      "  if (!accept('C')) return 3;" \
      "  if (accept('D')) return 4;" \
      "  return 0;" \
      "}" > param-eq-three.c
    check_return param-eq-three.c 0
    printf '%s\n' '#define VALUE 42' 'int main(void) { return VALUE; }' > define-return.c
    check_return define-return.c 42
    printf '%s\n' "#define LETTER 'A'" 'int main(void) { return LETTER; }' > define-char-return.c
    check_return define-char-return.c 65
    printf '%s\n' '#define VALUE 42' 'int main(void) { int VALUE = 7; return VALUE; }' > define-shadow.c
    check_return define-shadow.c 7
    printf '%s\n' '#define VALUE 42' 'int value_func(void) { return VALUE; }' 'int main(void) { return value_func(); }' > define-helper-return.c
    check_return define-helper-return.c 42
    printf '%s\n' "int letter_func(void) { return 'A'; }" 'int main(void) { return letter_func(); }' > helper-char-return.c
    check_return helper-char-return.c 65
    printf '%s\n' '#ifdef MISSING' 'int main(void) { return 1; }' '#else' 'int main(void) { return 42; }' '#endif' > ifdef-missing-else.c
    check_return ifdef-missing-else.c 42
    printf '%s\n' '#define VALUE 42' '#ifndef VALUE' 'int main(void) { return 1; }' '#else' 'int main(void) { return VALUE; }' '#endif' > ifndef-defined-else.c
    check_return ifndef-defined-else.c 42
    printf '%s\n' '#ifdef LATER' 'int main(void) { return 1; }' '#else' 'int main(void) { return 42; }' '#endif' '#define LATER 1' > define-after-ifdef.c
    check_return define-after-ifdef.c 42
    printf '%s\n' '#define VALUE 1' '#undef VALUE' '#ifdef VALUE' 'int main(void) { return 1; }' '#else' 'int main(void) { return 42; }' '#endif' > undef-before-ifdef.c
    check_return undef-before-ifdef.c 42
    printf '%s\n' '#define VALUE 1' '#undef VALUE' '#define VALUE 42' 'int main(void) { return VALUE; }' > undef-redefine.c
    check_return undef-redefine.c 42
    printf '%s\n' 'int main(voidx) { return 0; }' > keyword-prefix-param.c
    reject_compile keyword-prefix-param.c
    printf '%s\n' 'int main(void) { return sizeof(shorter); }' > keyword-prefix-sizeof.c
    reject_compile keyword-prefix-sizeof.c
    reject_compile ${testsRoot}/hcc/diagnostics/unknown-identifier.c
    reject_compile ${testsRoot}/hcc/diagnostics/unknown-global-initializer.c

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 ccc-host-ocaml "$out/bin/ccc-host-ocaml"
    runHook postInstall
  '';

  meta = {
    description = "OCaml-hosted development build of the CCC bootstrap C compiler";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
