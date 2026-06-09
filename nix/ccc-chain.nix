# Build the CCC bootstrap chain with a host C compiler (dev path):
#   mzvm + mlc-interp-seed, then the staged ML compilers
#   01-parenthetical -> 02-ml0 -> 03-adt -> 04-pattern,
# then the concatenated ccc sources compiled to bytecode by stage 04.
# Outputs:
#   bin/mzvm, bin/mlc-interp
#   lib/ccc/{01..04}.mzbc artifacts and ccc-cc1.mzbc
#   bin/ccc1 (wrapper: mzvm ccc-cc1.mzbc "$@")
# The M2-Planet-built variant of the seeds is future work; the staged ML
# tower and ccc bytecode are identical either way.
{ stdenv, cccSrc, pname ? "ccc-chain" }:

stdenv.mkDerivation {
  inherit pname;
  version = "unstable";
  src = cccSrc;

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    cc -O2 -o mzvm vm/mzvm.c
    cc -O2 -o mlc-interp seed/mlc-interp-seed.c

    run01() { ./mlc-interp stages/01-parenthetical.ml "$1" "$2"; }

    ./mlc-interp stages/02-ml0-compiler.ml stages/03-adt-compiler.ml 03.mzs
    run01 03.mzs 03.mzbc
    ./mzvm 03.mzbc stages/04-pattern-compiler.ml 04.mzs
    run01 04.mzs 04.mzbc

    # self-compilation fixpoint of the promoted compiler
    ./mzvm 04.mzbc stages/04-pattern-compiler.ml 04b.mzs
    run01 04b.mzs 04b.mzbc
    cmp 04.mzbc 04b.mzbc

    cat cc/[0-9]*.ml cc/dev/cc1main.ml > ccc-cc1.ml
    ./mzvm 04.mzbc ccc-cc1.ml ccc-cc1.mzs
    run01 ccc-cc1.mzs ccc-cc1.mzbc

    cat cc/00-util.ml cc/05-prim.ml cc/10-lexer.ml cc/12-symtab.ml \
        cc/18-literal.ml cc/20-ast.ml cc/22-constexpr.ml \
        cc/70-preproc.ml cc/72-include.ml cc/dev/cppmain.ml > ccpp.ml
    ./mzvm 04.mzbc ccpp.ml ccpp.mzs
    run01 ccpp.mzs ccpp.mzbc
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib/ccc
    install -m755 mzvm mlc-interp $out/bin/
    install -m644 03.mzbc 04.mzbc ccc-cc1.mzbc ccpp.mzbc $out/lib/ccc/
    cat > $out/bin/ccc1 <<EOF
    #!${stdenv.shell}
    exec $out/bin/mzvm $out/lib/ccc/ccc-cc1.mzbc "\$@"
    EOF
    cat > $out/bin/ccpp <<EOF
    #!${stdenv.shell}
    exec $out/bin/mzvm $out/lib/ccc/ccpp.mzbc "\$@"
    EOF
    chmod +x $out/bin/ccc1 $out/bin/ccpp
    runHook postInstall
  '';
}
