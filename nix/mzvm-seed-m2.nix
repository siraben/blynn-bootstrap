{
  stageRun,
  minimalBootstrap,
  mzvmSrc,
  scriptsRoot,
}:

stageRun {
  pname = "mzvm-seed-m2";
  nativeBuildInputs = [
    minimalBootstrap.stage0-posix.mescc-tools
  ];
  description = "M2-Planet-built seed ZINC-style VM for CCC bootstrap bytecode";
  buildScript = ''
    . ${scriptsRoot}/lib/bootstrap.sh
    cp ${mzvmSrc}/mzvm-seed.c mzvm-seed.c
    compile_m2 mzvm-seed.c mzvm-seed
    printf '%s\n' '#define MZVM_HEAP_LIMIT 16' '#include "mzvm-seed.c"' > mzvm-seed-gc.c
    compile_m2 mzvm-seed-gc.c mzvm-seed-gc
    printf '%b' '\115\132\102\103\001\000\000\000\060\000\000\000\003\000\000\000\000\000\000\000' > ok.mzbc
    printf '%b' '\001\117\000\000\000\016\001\000\000\000\001\000\000\000' >> ok.mzbc
    printf '%b' '\001\113\000\000\000\016\001\000\000\000\001\000\000\000' >> ok.mzbc
    printf '%b' '\001\012\000\000\000\016\001\000\000\000\001\000\000\000' >> ok.mzbc
    printf '%b' '\001\000\000\000\000\000' >> ok.mzbc
    ./mzvm-seed ok.mzbc > actual.txt
    IFS= read -r actual < actual.txt
    test "$actual" = OK
    printf '%b' '\115\132\102\103\001\000\000\000\143\000\000\000\003\000\000\000\000\000\000\000' > block.mzbc
    printf '%b' '\001\117\000\000\000\017\001\000\000\000\001\000\000\000\022\002\001\001\000\000\000\011\015\053\000\000\000' >> block.mzbc
    printf '%b' '\001\117\000\000\000\016\001\000\000\000\001\000\000\000' >> block.mzbc
    printf '%b' '\001\113\000\000\000\016\001\000\000\000\001\000\000\000' >> block.mzbc
    printf '%b' '\001\012\000\000\000\016\001\000\000\000\001\000\000\000\000' >> block.mzbc
    printf '%b' '\001\130\000\000\000\016\001\000\000\000\001\000\000\000' >> block.mzbc
    printf '%b' '\001\012\000\000\000\016\001\000\000\000\001\000\000\000\000' >> block.mzbc
    ./mzvm-seed block.mzbc > actual.txt
    IFS= read -r actual < actual.txt
    test "$actual" = OK
    printf '%b' '\115\132\102\103\001\000\000\000\106\000\000\000\003\000\000\000\000\000\000\000' > signed.mzbc
    printf '%b' '\001\377\377\377\377\002\001\000\000\000\000\012\015\012\000\000\000' >> signed.mzbc
    printf '%b' '\001\117\000\000\000\013\005\000\000\000\001\130\000\000\000' >> signed.mzbc
    printf '%b' '\016\001\000\000\000\001\000\000\000' >> signed.mzbc
    printf '%b' '\001\113\000\000\000\016\001\000\000\000\001\000\000\000' >> signed.mzbc
    printf '%b' '\001\012\000\000\000\016\001\000\000\000\001\000\000\000\000' >> signed.mzbc
    ./mzvm-seed signed.mzbc > actual.txt
    IFS= read -r actual < actual.txt
    test "$actual" = OK
    printf '%b' '\115\132\102\103\001\000\000\000\017\000\000\000\004\000\000\000\000\000\000\000' > debug.mzbc
    printf '%b' '\001\124\000\000\000\016\001\000\000\000\003\000\000\000\000' >> debug.mzbc
    ./mzvm-seed debug.mzbc > debug-out.txt 2> debug-err.txt
    test "$(cat debug-out.txt)" = ""
    test "$(cat debug-err.txt)" = T
    printf '%b' '\115\132\102\103\001\000\000\000\001\000\000\000\000\000\000\000\000\000\000\000\377' > bad-op.mzbc
    if ./mzvm-seed bad-op.mzbc > bad-op-out.txt 2> bad-op-err.txt; then
      exit 1
    fi
    test "$(cat bad-op-out.txt)" = ""
    case "$(cat bad-op-err.txt)" in
      *"unknown opcode pc=0 op=255 sp=0 rp=0"*) ;;
      *) exit 1 ;;
    esac
    i=0
    printf '%b' '\115\132\102\103\001\000\000\000\273\001\000\000\003\000\000\000\000\000\000\000' > gc.mzbc
    while [ "$i" -lt 20 ]; do
      printf '%b' '\001\001\000\000\000\002\001\002\000\000\000\017\000\000\000\000\002\000\000\000' >> gc.mzbc
      i=$((i + 1))
    done
    printf '%b' '\001\117\000\000\000\016\001\000\000\000\001\000\000\000' >> gc.mzbc
    printf '%b' '\001\113\000\000\000\016\001\000\000\000\001\000\000\000' >> gc.mzbc
    printf '%b' '\001\012\000\000\000\016\001\000\000\000\001\000\000\000' >> gc.mzbc
    printf '%b' '\000' >> gc.mzbc
    ./mzvm-seed-gc gc.mzbc > actual.txt
    IFS= read -r actual < actual.txt
    test "$actual" = OK
  '';
  installScript = ''
    install -Dm755 mzvm-seed "$out/bin/mzvm-seed"
    install -Dm755 mzvm-seed-gc "$out/bin/mzvm-seed-gc"
    install -Dm644 mzvm-seed.c "$out/share/mzvm/mzvm-seed.c"
    install -Dm644 mzvm-seed-gc.c "$out/share/mzvm/mzvm-seed-gc.c"
    install -Dm644 ok.mzbc "$out/share/mzvm/tests/ok.mzbc"
    install -Dm644 block.mzbc "$out/share/mzvm/tests/block.mzbc"
    install -Dm644 signed.mzbc "$out/share/mzvm/tests/signed.mzbc"
    install -Dm644 debug.mzbc "$out/share/mzvm/tests/debug.mzbc"
    install -Dm644 bad-op.mzbc "$out/share/mzvm/tests/bad-op.mzbc"
    install -Dm644 gc.mzbc "$out/share/mzvm/tests/gc.mzbc"
  '';
}
