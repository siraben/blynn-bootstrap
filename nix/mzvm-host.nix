{
  stdenv,
  lib,
  mzvmSrc,
  scriptsRoot,
}:

stdenv.mkDerivation {
  pname = "mzvm-host";
  version = "0-unstable-2026-05-06";
  src = mzvmSrc;

  dontConfigure = true;
  dontUpdateAutotoolsGnuConfigScripts = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -Wextra mzvm.c -o mzvm
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    sh ${scriptsRoot}/mzvm-write-ok-bytecode.sh ok.mzbc
    ./mzvm ok.mzbc > actual.txt
    printf 'OK\n' > expected.txt
    cmp expected.txt actual.txt
    $CC -O2 -Wall -Wextra -DMZVM_HEAP_LIMIT=16 mzvm.c -o mzvm-gc
    sh ${scriptsRoot}/mzvm-write-gc-bytecode.sh gc.mzbc
    ./mzvm-gc gc.mzbc > gc-actual.txt
    cmp expected.txt gc-actual.txt
    sh ${scriptsRoot}/mzvm-write-signed-bytecode.sh signed.mzbc
    ./mzvm signed.mzbc > signed-actual.txt
    cmp expected.txt signed-actual.txt
    printf '%b' '\115\132\102\103\001\000\000\000\017\000\000\000\004\000\000\000\000\000\000\000' > debug.mzbc
    printf '%b' '\001\124\000\000\000\016\001\000\000\000\003\000\000\000\000' >> debug.mzbc
    ./mzvm debug.mzbc > debug-out.txt 2> debug-err.txt
    test "$(cat debug-out.txt)" = ""
    test "$(cat debug-err.txt)" = T
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 mzvm "$out/bin/mzvm"
    install -Dm644 mzvm.c "$out/share/mzvm/mzvm.c"
    install -Dm644 mzvm-seed.c "$out/share/mzvm/mzvm-seed.c"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Host-built development ZINC-style VM for CCC bootstrap bytecode";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
