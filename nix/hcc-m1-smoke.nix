{
  stdenvNoCC,
  lib,
  hcc,
  minimalBootstrap,
  m2libc,
}:

stdenvNoCC.mkDerivation {
  pname = "hcc-m1-smoke";
  version = "0-unstable-2026-05-06";

  nativeBuildInputs = [
    hcc
    minimalBootstrap.stage0-posix.mescc-tools
  ];

  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    cat > ret13.c <<'EOF'
    int main(){return 13;}
    EOF

    hcc -S -o ret13.M1 ret13.c
    M1 --architecture amd64 --little-endian \
      -f ${m2libc}/amd64/amd64_defs.M1 \
      -f ${m2libc}/amd64/libc-core.M1 \
      -f ret13.M1 \
      --output ret13.hex2
    printf ':ELF_end\n' > end.hex2
    hex2 --architecture amd64 --little-endian --base-address 0x00600000 \
      --file ${m2libc}/amd64/ELF-amd64.hex2 \
      --file ret13.hex2 \
      --file end.hex2 \
      --output ret13
    chmod +x ret13
    set +e
    ./ret13
    code=$?
    set -e
    test "$code" = 13
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/hcc-m1-smoke
    cp ret13 $out/bin/
    cp ret13.c ret13.M1 ret13.hex2 $out/share/hcc-m1-smoke/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Smoke test for hcc M1 output assembled by stage0-posix tools";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
