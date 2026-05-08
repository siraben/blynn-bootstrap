{
  stdenvNoCC,
  lib,
  hcc,
  minimalBootstrap,
  m2libc,
  python3,
}:

stdenvNoCC.mkDerivation {
  pname = "hcc-m1-smoke";
  version = "0-unstable-2026-05-06";

  nativeBuildInputs = [
    hcc
    minimalBootstrap.stage0-posix.mescc-tools
    python3
  ];

  dontUnpack = true;

  buildPhase = ''
    runHook preBuild

    python3 ${../vendor/hcc/test/m1-smoke/run.py} \
      --m2libc ${m2libc} \
      --source-dir ${../vendor/hcc/test/m1-smoke} \
      --work-dir .

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/hcc-m1-smoke
    cp ret13 $out/bin/
    cp ${../vendor/hcc/test/m1-smoke}/examples/*.c *.i *.M1 *.hex2 $out/share/hcc-m1-smoke/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Smoke test for hcc M1 output assembled by stage0-posix tools";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
