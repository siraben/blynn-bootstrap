{
  stageRun,
  lib,
  minimalBootstrap,
  mlcSrc,
  mzvmSeedM2,
  scriptsRoot,
  testsMlc,
}:

let
  seedFixtures = import ./mlc-seed-fixtures.nix;
  fixtures = lib.concatStringsSep " " seedFixtures.fixtures;
  inputFixtures = lib.concatStringsSep " " seedFixtures.inputFixtures;
in
stageRun {
  pname = "mlc-seed-m2";
  nativeBuildInputs = [
    minimalBootstrap.stage0-posix.mescc-tools
  ];
  description = "M2-Planet-built seed mini-OCaml compiler for CCC bootstrap bytecode";
  buildScript = ''
    . ${scriptsRoot}/lib/bootstrap.sh
    cp ${mlcSrc}/mlc-seed.c mlc-seed.c
    for name in ${fixtures} ${inputFixtures}; do
      cp ${testsMlc}/$name.ml $name.ml
    done
    compile_m2 mlc-seed.c mlc-seed

    run_check() {
      name="$1"
      expected="$2"
      ./mlc-seed "$name.ml" "$name.mzbc"
      actual="$(${mzvmSeedM2}/bin/mzvm-seed "$name.mzbc")"
      test "$actual" = "$expected"
    }

    run_check ok OK
    run_check arithmetic H-
    run_check conditional OK
    run_check comparison "$(printf 'OK\nOK')"
    run_check negative OK
    run_check let-binding OK
    run_check array OK
    run_check bytes OK
    run_check string-value OK
    run_check dynamic-index OK
    run_check dynamic-create OK
    run_check length OK
    run_check function OK
    run_check function-tuple OK
    run_check function-nested OK
    run_check function-string OK
    run_check function-and OK
    run_check identifiers O
    run_check string "$(printf 'O\tK')"
    run_check exit OK
    run_check tuple OK
    run_check sequence OK
    ./mlc-seed read-byte.ml read-byte.mzbc
    printf 'O' > input.txt
    actual="$(${mzvmSeedM2}/bin/mzvm-seed read-byte.mzbc < input.txt)"
    test "$actual" = OK
  '';
  installScript = ''
    install -Dm755 mlc-seed "$out/bin/mlc-seed"
    install -Dm644 mlc-seed.c "$out/share/mlc/mlc-seed.c"
    for name in ${fixtures} ${inputFixtures}; do
      install -Dm644 "$name.mzbc" "$out/share/mlc/tests/$name.mzbc"
    done
  '';
}
