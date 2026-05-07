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

    assemble_and_run() {
      name="$1"
      expected="$2"

      hcc -S -o "$name.M1" "$name.c"
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
      code=$?
      set -e
      test "$code" = "$expected"
    }

    cat > ret13.c <<'EOF'
    int main(){return 13;}
    EOF

    cat > short-circuit.c <<'EOF'
    int boom(int *p){return *p;}
    int main(){
      int *p = 0;
      if (0 && boom(p)) return 1;
      if ((0 && boom(p)) || (1 && 42)) return 42;
      return 2;
    }
    EOF

    assemble_and_run ret13 13
    assemble_and_run short-circuit 42
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share/hcc-m1-smoke
    cp ret13 $out/bin/
    cp *.c *.M1 *.hex2 $out/share/hcc-m1-smoke/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Smoke test for hcc M1 output assembled by stage0-posix tools";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
  };
}
