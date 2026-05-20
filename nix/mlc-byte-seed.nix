{
  stageRun,
  mlcSrc,
  mlcStage02Ml0Compiler,
  mzvmSeedM2,
}:

stageRun {
  pname = "mlc-byte-seed";
  nativeBuildInputs = [
    mzvmSeedM2
  ];
  description = "Current mlc.ml compiled to MZBC by the staged ML0 compiler";
  buildScript = ''
    cp ${mlcStage02Ml0Compiler}/share/mlc/stages/mlc-stage-from-02-self.mzbc mlc.bootstrap.byte
    ${mzvmSeedM2}/bin/mzvm-seed mlc.bootstrap.byte < ${mlcSrc}/mlc.ml > mlc.byte

    printf 'write_byte (40+39)' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > compiled-smoke.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed compiled-smoke.mzbc)"
    test "$actual" = O
  '';
  installScript = ''
    install -Dm644 mlc.bootstrap.byte "$out/share/mlc/mlc.bootstrap.byte"
    install -Dm644 mlc.byte "$out/share/mlc/mlc.byte"
    install -Dm644 compiled-smoke.mzbc "$out/share/mlc/compiled-smoke.mzbc"
  '';
}
