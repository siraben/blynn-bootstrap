{
  stdenv,
  lib,
  mlcSrc,
  mzvmHost,
  testsMlc,
}:

let
  seedFixtures = import ./mlc-seed-fixtures.nix;
  fixtures = lib.concatStringsSep " " seedFixtures.fixtures;
  inputFixtures = lib.concatStringsSep " " seedFixtures.inputFixtures;
in
stdenv.mkDerivation {
  pname = "mlc-seed-host";
  version = "0-unstable-2026-05-06";
  src = mlcSrc;

  dontConfigure = true;
  dontUpdateAutotoolsGnuConfigScripts = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -Wextra mlc-seed.c -o mlc-seed
    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    for name in ${fixtures}; do
      ./mlc-seed ${testsMlc}/$name.ml $name.mzbc
      ${mzvmHost}/bin/mzvm $name.mzbc > $name.out
    done
    for name in ${inputFixtures}; do
      ./mlc-seed ${testsMlc}/$name.ml $name.mzbc
    done
    printf 'O' | ${mzvmHost}/bin/mzvm read-byte.mzbc > read-byte.out
    printf 'OK\n' > ok.expected
    printf 'H-\n' > arithmetic.expected
    printf 'OK\n' > conditional.expected
    printf 'OK\nOK\n' > comparison.expected
    printf 'OK\n' > negative.expected
    printf 'OK\n' > let-binding.expected
    printf 'OK\n' > array.expected
    printf 'OK\n' > bytes.expected
    printf 'OK\n' > string-value.expected
    printf 'OK\n' > dynamic-index.expected
    printf 'OK\n' > dynamic-create.expected
    printf 'OK\n' > length.expected
    printf 'OK\n' > function.expected
    printf 'OK\n' > function-tuple.expected
    printf 'OK\n' > function-nested.expected
    printf 'OK\n' > function-string.expected
    printf 'OK\n' > function-and.expected
    printf 'O\n' > identifiers.expected
    printf 'O\tK\n' > string.expected
    printf 'OK\n' > exit.expected
    printf 'OK\n' > tuple.expected
    printf 'OK\n' > sequence.expected
    printf 'OK\n' > read-byte.expected
    for name in ${fixtures}; do
      cmp $name.expected $name.out
    done
    cmp read-byte.expected read-byte.out
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 mlc-seed "$out/bin/mlc-seed"
    install -Dm644 mlc-seed.c "$out/share/mlc/mlc-seed.c"
    for name in ${fixtures}; do
      install -Dm644 $name.mzbc "$out/share/mlc/tests/$name.mzbc"
    done
    install -Dm644 read-byte.mzbc "$out/share/mlc/tests/read-byte.mzbc"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Host-built seed mini-OCaml compiler for CCC bootstrap bytecode";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
