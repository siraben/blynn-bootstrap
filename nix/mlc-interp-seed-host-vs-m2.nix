{
  runCommand,
  mlcInterpSeedHost,
  mlcInterpSeedM2,
}:

runCommand "mlc-interp-seed-host-vs-m2" { } ''
  cmp ${mlcInterpSeedHost}/share/mlc/stages/00-core.out ${mlcInterpSeedM2}/share/mlc/stages/00-core.out
  install -Dm644 ${mlcInterpSeedHost}/share/mlc/stages/00-core.out "$out/00-core.out"
''
