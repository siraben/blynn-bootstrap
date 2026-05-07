{
  stdenvNoCC,
  lib,
  hcc,
  minimalBootstrap,
  m2libc,
  mesTests,
}:

stdenvNoCC.mkDerivation {
  pname = "hcc-mescc-tests";
  version = "0-unstable-2026-05-06";

  nativeBuildInputs = [
    hcc
    minimalBootstrap.stage0-posix.mescc-tools
  ];

  dontUnpack = true;

  buildPhase = ''
    runHook preBuild

    assemble_and_run() {
      name="$1"
      expected="$2"
      src="${mesTests}/scaffold/$name.c"

      hcc -S -o "$name.M1" "$src"
      M1 --architecture amd64 --little-endian \
        -f ${m2libc}/amd64/amd64_defs.M1 \
        -f ${m2libc}/amd64/libc-core.M1 \
        -f "$name.M1" \
        --output "$name.hex2"
      printf ':ELF_end\n' > "$name-end.hex2"
      hex2 --architecture amd64 --little-endian --base-address 0x00600000 \
        --file ${m2libc}/amd64/ELF-amd64.hex2 \
        --file "$name.hex2" \
        --file "$name-end.hex2" \
        --output "$name"
      chmod +x "$name"

      set +e
      "./$name"
      code="$?"
      set -e
      if test "$code" != "$expected"; then
        echo "$name: expected exit $expected, got $code" >&2
        exit 1
      fi
    }

    assemble_and_run 01-return-0 0
    assemble_and_run 02-return-1 1
    assemble_and_run 03-call 0
    assemble_and_run 04-call-0 0
    assemble_and_run 05-call-1 1
    assemble_and_run 06-call-2 0
    assemble_and_run 06-call-not-1 0
    assemble_and_run 06-not-call-1 0
    assemble_and_run 06-return-void 0
    assemble_and_run 08-assign-negative 0
    assemble_and_run 08-assign 0
    assemble_and_run 10-if-0 0
    assemble_and_run 11-if-1 0
    assemble_and_run 12-if-eq 0
    assemble_and_run 13-if-neq 0
    assemble_and_run 14-if-goto 0
    assemble_and_run 15-if-not-f 0
    assemble_and_run 16-cast 0
    assemble_and_run 16-if-t 0
    assemble_and_run 17-compare-lt 0
    assemble_and_run 17-compare-le 0
    assemble_and_run 17-compare-gt 0
    assemble_and_run 17-compare-ge 0
    assemble_and_run 17-compare-char 0
    assemble_and_run 17-compare-and 0
    assemble_and_run 17-compare-or 0
    assemble_and_run 17-compare-assign 0
    assemble_and_run 17-compare-call 0
    assemble_and_run 17-compare-rotated 0
    assemble_and_run 18-assign-shadow 0
    assemble_and_run 20-while 0
    assemble_and_run 21-char-array-simple 0
    assemble_and_run 21-char-array 0
    assemble_and_run 22-while-char-array 0
    assemble_and_run 30-exit-0 0
    assemble_and_run 30-exit-42 42
    assemble_and_run 33-and-or 0
    assemble_and_run 36-compare-arithmetic 0
    assemble_and_run 36-compare-arithmetic-negative 0
    assemble_and_run 37-compare-assign 0
    assemble_and_run 40-if-else 0
    assemble_and_run 42-goto-label 0
    assemble_and_run 45-void-call 0
    assemble_and_run 70-function-modulo 0

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/hcc-mescc-tests
    cp *.M1 *.hex2 $out/share/hcc-mescc-tests/
    runHook postInstall
  '';

  meta = with lib; {
    description = "MesCC scaffold tests compiled by hcc to M1 and assembled by stage0-posix tools";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
