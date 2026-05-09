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
  dontPatch = true;
  dontConfigure = true;
  dontUpdateAutotoolsGnuConfigScripts = true;
  dontFixup = true;
  dontPatchELF = true;

  buildPhase = ''
    runHook preBuild

    echo "hcc-m1-smoke: using hcc=${hcc}"
    echo "hcc-m1-smoke: using m2libc=${m2libc}"
    echo "hcc-m1-smoke: source-dir=${../tests/hcc/m1-smoke}"
    echo "hcc-m1-smoke: START python smoke runner"
    python3 ${../tests/hcc/m1-smoke/run.py} \
      --m2libc ${m2libc} \
      --source-dir ${../tests/hcc/m1-smoke} \
      --work-dir .
    echo "hcc-m1-smoke: DONE python smoke runner"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/hcc-m1-smoke
    cp ret13 $out/bin/
    cp ${../tests/hcc/m1-smoke}/examples/*.c *.i *.hccir *.M1 *.hex2 $out/share/hcc-m1-smoke/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Smoke test for hcc M1 output assembled by stage0-posix tools";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
