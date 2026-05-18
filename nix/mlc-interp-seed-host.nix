{
  stdenv,
  lib,
  mlcSrc,
}:

stdenv.mkDerivation {
  pname = "mlc-interp-seed-host";
  version = "0-unstable-2026-05-17";
  src = mlcSrc;

  dontConfigure = true;
  dontUpdateAutotoolsGnuConfigScripts = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -Wextra mlc-interp-seed.c -o mlc-interp-seed
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./mlc-interp-seed stages/00-core.ml > 00-core.out
    printf 'OOK\n' > 00-core.expected
    cmp 00-core.expected 00-core.out
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 mlc-interp-seed "$out/bin/mlc-interp-seed"
    install -Dm644 mlc-interp-seed.c "$out/share/mlc/mlc-interp-seed.c"
    install -Dm644 stages/00-core.ml "$out/share/mlc/stages/00-core.ml"
    install -Dm644 00-core.out "$out/share/mlc/stages/00-core.out"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Host-built tree-walking mini-OCaml bootstrap interpreter";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
