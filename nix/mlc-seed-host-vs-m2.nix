{
  runCommand,
  lib,
  mlcSeedHost,
  mlcSeedM2,
}:

let
  seedFixtures = import ./mlc-seed-fixtures.nix;
  fixtures = lib.concatStringsSep " " seedFixtures.fixtures;
  inputFixtures = lib.concatStringsSep " " seedFixtures.inputFixtures;
in
runCommand "mlc-seed-host-vs-m2" { } ''
  for name in ${fixtures}; do
    cmp ${mlcSeedHost}/share/mlc/tests/$name.mzbc ${mlcSeedM2}/share/mlc/tests/$name.mzbc
  done
  for name in ${inputFixtures}; do
    cmp ${mlcSeedHost}/share/mlc/tests/$name.mzbc ${mlcSeedM2}/share/mlc/tests/$name.mzbc
  done
  install -Dm644 ${mlcSeedHost}/share/mlc/tests/ok.mzbc "$out/ok.mzbc"
''
