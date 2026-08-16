{
  stdenv,
  lib,
  hcc,
  pname ? "hcc-elf-smoke",
}:

let
  nixLib = import ./lib.nix { inherit lib; };
in
stdenv.mkDerivation (
  {
    inherit pname;
    version = nixLib.bootstrapVersion;
  }
  // nixLib.scriptOnly
  // {
    nativeBuildInputs = [ hcc ];

    buildPhase = ''
      runHook preBuild

      cc -std=c89 -pedantic -Wall -Wextra -Werror \
        ${../hcc/cbits/m1_to_gas.c} -o m1-to-gas
      hcpp ${../tests/hcc/elf-smoke/variadic-libc.c} > variadic-libc.i
      hcc1 --target amd64 --data-prefix variadic-libc --m1-ir \
        -o variadic-libc.hccir variadic-libc.i
      hcc-m1 --target amd64 variadic-libc.hccir variadic-libc.M1
      ./m1-to-gas variadic-libc.M1 variadic-libc.s
      cc -no-pie variadic-libc.s -o variadic-libc
      ./variadic-libc

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm555 m1-to-gas "$out/bin/m1-to-gas"
      install -Dm555 variadic-libc "$out/bin/variadic-libc"
      install -Dm644 variadic-libc.M1 "$out/share/hcc-elf-smoke/variadic-libc.M1"
      install -Dm644 variadic-libc.s "$out/share/hcc-elf-smoke/variadic-libc.s"
      runHook postInstall
    '';

    meta = {
      description = "HCC M1-to-ELF and native libc ABI smoke test";
      platforms = lib.platforms.x86_64;
    };
  }
)
