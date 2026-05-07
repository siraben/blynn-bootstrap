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
