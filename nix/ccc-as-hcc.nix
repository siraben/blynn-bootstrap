# The CCC chain built from M2-Planet only (no host C compiler, no ML
# tooling), packaged with the hcpp/hcc1/hcc-m1 command-line interface so
# nix/tinycc-boot-hcc.nix can consume it unchanged:
#   bin/hcpp   -> mzvm ccpp.mzbc   (ML preprocessor)
#   bin/hcc1   -> mzvm ccc-cc1.mzbc (ML C compiler; --m1-ir -o OUT IN)
#   bin/hcc-m1 -> M2-Planet-built hcc_m1.c backend
# Every step of the build is timestamped into share/ccc-as-hcc/timing.
{ lib, stdenvNoCC, minimalBootstrap, cccSrc, hccSrc, pname ? "ccc-as-hcc" }:

stdenvNoCC.mkDerivation {
  inherit pname;
  version = "unstable";
  src = cccSrc;

  nativeBuildInputs = [ minimalBootstrap.stage0-posix.mescc-tools ];

  M2_ARCH = minimalBootstrap.stage0-posix.m2libcArch;
  M2_OS = minimalBootstrap.stage0-posix.m2libcOS;
  M2LIBC_PATH = "${minimalBootstrap.stage0-posix.src}/M2libc";

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    ulimit -s unlimited
    . ${../scripts/lib/bootstrap.sh}

    : > timing
    mark() {
      now=$(date +%s)
      if [ -n "''${last:-}" ]; then
        printf '%-32s %ss\n' "$1" "$((now - last))" | tee -a timing
      else
        printf '%-32s start\n' "$1" | tee -a timing
      fi
      last=$now
    }

    mark begin
    compile_m2 vm/mzvm.c mzvm
    compile_m2 seed/mlc-interp-seed.c mlc-interp
    mark "m2: seeds (mzvm, mlc-interp)"

    # The tree-walking mlc-interp never frees its arena, so it is only used
    # for the small early-stage assemblies. As soon as stage 04 (a real
    # bytecode compiler) exists, stage 01 is itself compiled to bytecode and
    # all large assemblies run on the GC-backed VM instead.
    run01() { ./mlc-interp stages/01-parenthetical.ml "$1" "$2"; }

    ./mlc-interp stages/02-ml0-compiler.ml stages/03-adt-compiler.ml 03.mzs
    run01 03.mzs 03.mzbc
    ./mzvm 03.mzbc stages/04-pattern-compiler.ml 04.mzs
    run01 04.mzs 04.mzbc
    ./mzvm 04.mzbc stages/04-pattern-compiler.ml 04b.mzs
    run01 04b.mzs 04b.mzbc
    cmp 04.mzbc 04b.mzbc
    mark "staged ML bootstrap + fixpoint"

    # Bootstrap a bytecode stage-01 assembler (small input, fine under the
    # interpreter), then assemble everything large on the VM.
    ./mzvm 04.mzbc stages/01-parenthetical.ml 01.mzs
    run01 01.mzs 01.mzbc
    runasm() { ./mzvm 01.mzbc "$1" "$2"; }
    mark "bootstrap bytecode assembler"

    # type-check gate: every promoted ML source must pass the HM checker
    # (which is itself type-checked) before anything is compiled from it
    ./mzvm 04.mzbc mlc/mltc.ml mltc.mzs
    runasm mltc.mzs mltc.mzbc
    typecheck() { ./mzvm mltc.mzbc "$1"; }
    typecheck mlc/mltc.ml
    typecheck stages/01-parenthetical.ml
    typecheck stages/02-ml0-compiler.ml
    typecheck stages/03-adt-compiler.ml
    typecheck stages/04-pattern-compiler.ml
    mark "mltc type-check gate (stages)"

    cat cc/[0-9]*.ml cc/dev/cc1main.ml > ccc-cc1.ml
    typecheck ccc-cc1.ml
    ./mzvm 04.mzbc ccc-cc1.ml ccc-cc1.mzs
    runasm ccc-cc1.mzs ccc-cc1.mzbc
    cat cc/00-util.ml cc/05-prim.ml cc/10-lexer.ml cc/12-symtab.ml \
        cc/18-literal.ml cc/20-ast.ml cc/22-constexpr.ml \
        cc/70-preproc.ml cc/72-include.ml cc/dev/cppmain.ml > ccpp.ml
    typecheck ccpp.ml
    ./mzvm 04.mzbc ccpp.ml ccpp.mzs
    runasm ccpp.mzs ccpp.mzbc
    mark "ccc1 + ccpp bytecode (type-checked)"

    mkdir -p cbits
    cp ${hccSrc}/cbits/hcc_m1.c cbits/hcc_m1.c
    cp ${hccSrc}/cbits/hcc_m1_arch_aarch64.c cbits/
    cp ${hccSrc}/cbits/hcc_m1_arch_riscv64.c cbits/
    compile_m2 cbits/hcc_m1.c hcc-m1
    mark "m2: hcc-m1 backend"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib/ccc $out/share/ccc-as-hcc
    install -m755 mzvm mlc-interp hcc-m1 $out/bin/
    install -m644 04.mzbc ccc-cc1.mzbc ccpp.mzbc $out/lib/ccc/
    install -m644 timing $out/share/ccc-as-hcc/timing

    cat > $out/bin/hcpp <<EOF
    #!${stdenvNoCC.shell}
    exec $out/bin/mzvm $out/lib/ccc/ccpp.mzbc "\$@"
    EOF

    # hcc1 CLI shim: accept "--m1-ir -o OUT [flags] IN", run "ccc1 IN OUT"
    cat > $out/bin/hcc1 <<EOF
    #!${stdenvNoCC.shell}
    out=""
    input=""
    while [ \$# -gt 0 ]; do
      case "\$1" in
        -o) out=\$2; shift 2 ;;
        --m1-ir|--trace|-S|-c) shift ;;
        --target) shift 2 ;;
        -*) echo "hcc1: unsupported option: \$1" >&2; exit 1 ;;
        *) input=\$1; shift ;;
      esac
    done
    if [ -z "\$input" ] || [ -z "\$out" ]; then
      echo "usage: hcc1 --m1-ir -o FILE INPUT.i" >&2; exit 1
    fi
    exec $out/bin/mzvm $out/lib/ccc/ccc-cc1.mzbc "\$input" "\$out"
    EOF
    chmod +x $out/bin/hcpp $out/bin/hcc1
    runHook postInstall
  '';
}
