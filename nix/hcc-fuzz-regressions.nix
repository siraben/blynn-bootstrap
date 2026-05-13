{
  stdenvNoCC,
  lib,
  hcc,
  bash,
  coreutils,
  pname ? "hcc-fuzz-regressions",
  tests,
}:

stdenvNoCC.mkDerivation {
  inherit pname;
  version = "0";

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  nativeBuildInputs = [
    bash
    coreutils
    hcc
  ];

  installPhase = ''
    runHook preInstall
    export PATH=${coreutils}/bin:${bash}/bin:${hcc}/bin
    HCC1=${hcc}/bin/hcc1 ${bash}/bin/sh ${tests}/hcc/fuzz-regressions/run.sh
    mkdir -p $out/share/hcc-fuzz-regressions
    cp -R ${tests}/hcc/fuzz-regressions/cases $out/share/hcc-fuzz-regressions/
    runHook postInstall
  '';

  meta = with lib; {
    description = "No-crash regression tests for hcc fuzz findings";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
