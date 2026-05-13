{
  stdenvNoCC,
  stdenv,
  lib,
  pname ? "hcc-m1-smoke",
  hcc,
  minimalBootstrap,
  m2libc,
  python3,
  qemu,
  target ? "amd64",
}:

let
  nixLib = import ./lib.nix { inherit lib; };
  needsAarch64Runner = target == "aarch64" && stdenv.hostPlatform.system != "aarch64-linux";
  runnerArgs =
    lib.optionalString needsAarch64Runner "--runner ${qemu}/bin/qemu-aarch64";
in
stdenvNoCC.mkDerivation (
  {
    inherit pname;
    version = nixLib.bootstrapVersion;
  }
  // nixLib.scriptOnly
  // {

    nativeBuildInputs = [
      hcc
      minimalBootstrap.stage0-posix.mescc-tools
      python3
    ] ++ lib.optional needsAarch64Runner qemu;

    buildPhase = ''
      runHook preBuild

      echo "hcc-m1-smoke: using hcc=${hcc}"
      echo "hcc-m1-smoke: using m2libc=${m2libc}"
      echo "hcc-m1-smoke: source-dir=${../tests/hcc/m1-smoke}"
      echo "hcc-m1-smoke: START python smoke runner"
      python3 ${../tests/hcc/m1-smoke/run.py} \
        --m2libc ${m2libc} \
        --source-dir ${../tests/hcc/m1-smoke} \
        --work-dir . \
        --target ${target} \
        ${runnerArgs}
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
)
