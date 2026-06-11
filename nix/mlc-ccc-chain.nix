{
  pkgs,
  stageRun,
  minimalBootstrap,
  mlcSrc,
  cccSrc,
  mzvmHost,
  mzvmSeedM2,
  testsRoot,
  scriptsRoot,
}:

let
  testsMlc = testsRoot + "/mlc";
in
rec {
  mlcInterpSeedHost = pkgs.callPackage ./mlc-interp-seed-host.nix {
    inherit mlcSrc;
  };

  mlcInterpSeedM2 = pkgs.callPackage ./mlc-interp-seed-m2.nix {
    inherit stageRun minimalBootstrap mlcSrc scriptsRoot;
  };

  mlcInterpSeedHostVsM2 = pkgs.callPackage ./mlc-interp-seed-host-vs-m2.nix {
    runCommand = pkgs.runCommand;
    inherit mlcInterpSeedHost mlcInterpSeedM2;
  };

  mlcStage00Core = pkgs.callPackage ./mlc-stage-00-core.nix {
    inherit stageRun mlcSrc mlcInterpSeedM2;
  };

  mlcStage01Parenthetical = pkgs.callPackage ./mlc-stage-01-parenthetical.nix {
    inherit stageRun mlcSrc mlcInterpSeedM2 mzvmSeedM2;
  };

  mlcStage02CoreLambda = pkgs.callPackage ./mlc-stage-02-core-lambda.nix {
    inherit stageRun mlcSrc mlcInterpSeedM2 mzvmSeedM2;
  };

  mlcStage03CoreHandoff = pkgs.callPackage ./mlc-stage-03-core-handoff.nix {
    inherit stageRun mlcSrc mlcInterpSeedM2 mlcStage02CoreLambda mzvmSeedM2;
  };

  mlcStage04Ok = pkgs.callPackage ./mlc-stage-04-ok.nix {
    inherit stageRun mlcSrc mlcStage03CoreHandoff mzvmSeedM2;
  };

  mlcStage04Ml0Compiler = pkgs.callPackage ./mlc-stage-04-ml0-compiler.nix {
    inherit stageRun mlcSrc mlcInterpSeedM2 mzvmSeedM2 testsMlc;
  };

  mlcCoreLambdaRootVsMl0 = pkgs.runCommand "mlc-core-lambda-root-vs-ml0" { } ''
    ${mzvmSeedM2}/bin/mzvm-seed ${mlcStage04Ml0Compiler}/share/mlc/stages/04-self.mzbc < ${mlcSrc}/stages/02-core-lambda.ml > core-lambda-ml0.mzbc
    check() {
      printf '%s' "$1" | ${mlcInterpSeedM2}/bin/mlc-interp-seed ${mlcSrc}/stages/02-core-lambda.ml > root.mzbc
      printf '%s' "$1" | ${mzvmSeedM2}/bin/mzvm-seed core-lambda-ml0.mzbc > ml0.mzbc
      cmp root.mzbc ml0.mzbc
    }
    check "(20 (write-byte 'O'))"
    check '(34 (write-string "OK"))'
    check '(38 (let 40 (write-byte (+ (var 0) 39))))'
    check "(49 (app (fun 5 26 (write-byte (+ (var 0) 39))) 40))"
    check '(120 (seq (need-string "OK") (write-byte 89)))'
    install -Dm644 core-lambda-ml0.mzbc "$out/share/mlc/stages/core-lambda-ml0.mzbc"
  '';

  mlcSeedHost = pkgs.callPackage ./mlc-seed-host.nix {
    inherit mlcSrc mzvmHost testsMlc;
  };

  mlcSeedM2 = pkgs.callPackage ./mlc-seed-m2.nix {
    inherit stageRun minimalBootstrap mlcSrc mzvmSeedM2 scriptsRoot testsMlc;
  };

  mlcSeedHostVsM2 = pkgs.callPackage ./mlc-seed-host-vs-m2.nix {
    runCommand = pkgs.runCommand;
    inherit mlcSeedHost mlcSeedM2;
  };

  mlcByteSeed = pkgs.callPackage ./mlc-byte-seed.nix {
    inherit stageRun mlcSrc mlcStage04Ml0Compiler mzvmSeedM2;
  };

  mlcByteCorpus = pkgs.callPackage ./mlc-byte-corpus.nix {
    inherit stageRun testsRoot mlcByteSeed mzvmSeedM2;
    diffutils = pkgs.diffutils;
  };

  mlcByteCommitted = pkgs.runCommand "mlc-byte-committed" { } ''
    cmp ${mlcSrc}/mlc.byte ${mlcByteSeed}/share/mlc/mlc.byte
    install -Dm644 ${mlcSrc}/mlc.byte "$out/share/mlc/mlc.byte"
  '';

  mlcByteCommittedSmoke = pkgs.runCommand "mlc-byte-committed-smoke" { } ''
    cp ${mlcSrc}/mlc.byte mlc.byte

    printf 'let x = 79 in write_byte x' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > good.mzbc
    actual="$(${mzvmSeedM2}/bin/mzvm-seed good.mzbc)"
    test "$actual" = O

    if printf 'let x = 79 in write_byte x.' | ${mzvmSeedM2}/bin/mzvm-seed mlc.byte > bad-consumed-dot.mzbc; then
      echo "mlc.byte should reject consumed-dot postfixes" >&2
      exit 1
    else
      :
    fi

    mkdir -p "$out/share/mlc"
    printf '%s\n' OK > "$out/share/mlc/committed-smoke.txt"
  '';

  mlcByteSelfhost = pkgs.runCommand "mlc-byte-selfhost" { } ''
    ${mzvmSeedM2}/bin/mzvm-seed ${mlcByteSeed}/share/mlc/mlc.byte < ${mlcSrc}/mlc.ml > compiled-selfhost.mzbc
    cmp ${mlcByteSeed}/share/mlc/mlc.byte compiled-selfhost.mzbc
    install -Dm644 ${mlcByteSeed}/share/mlc/mlc.byte "$out/share/mlc/mlc.byte"
    install -Dm644 compiled-selfhost.mzbc "$out/share/mlc/compiled-selfhost.mzbc"
  '';

  mlcStage05AstCompiler = pkgs.callPackage ./mlc-stage-05-ast-compiler.nix {
    inherit stageRun mlcSrc mzvmSeedM2;
    mlcByte = mlcSrc + "/mlc.byte";
  };

  cccByteSeed = pkgs.callPackage ./ccc-byte-seed.nix {
    inherit stageRun cccSrc mzvmSeedM2 mlcByteCommitted testsRoot;
  };

  cccByteCommitted = pkgs.runCommand "ccc-byte-committed" { } ''
    cmp ${cccSrc}/ccc.byte ${cccByteSeed}/share/ccc/ccc.byte
    install -Dm644 ${cccSrc}/ccc.byte "$out/share/ccc/ccc.byte"
  '';

  tccM1CccSeed = pkgs.runCommand "tcc-m1-ccc-seed" { } ''
    ${mzvmSeedM2}/bin/mzvm-seed ${cccByteCommitted}/share/ccc/ccc.byte < ${testsRoot}/mescc/scaffold/01-return-0.c > tcc.M1
    printf 'DEFINE LOADI32_RDI 48C7C7\nDEFINE LOADI32_RAX 48C7C0\nDEFINE SYSCALL 0F05\n\n:_start\n\tLOADI32_RDI %%0\n\tLOADI32_RAX %%60\n\tSYSCALL\n' > expected.M1
    cmp expected.M1 tcc.M1
    install -Dm644 tcc.M1 "$out/share/ccc/tcc.M1"
  '';

  tccBinCccSeed = pkgs.callPackage ./tcc-bin-ccc-seed.nix {
    runCommand = pkgs.runCommand;
    inherit mzvmSeedM2 cccByteCommitted tccM1CccSeed testsRoot;
    mesccTools = minimalBootstrap.stage0-posix.mescc-tools;
    stage0Src = minimalBootstrap.stage0-posix.src;
  };
}
