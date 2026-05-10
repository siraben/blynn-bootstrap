{
  lib,
  buildPlatform,
  hostPlatform,
  fetchurl,
  bash,
  tinycc,
  gnumakeBoot,
  gnupatch,
  gnused,
  gnugrep,
  gawk,
  gnutar,
  gzip,
  nixpkgsPath,
}:
let
  inherit (import ./common.nix { inherit lib; }) meta;
  pname = "gnumake-musl";
  version = "4.4.1";

  src = fetchurl {
    url = "mirror://gnu/make/make-${version}.tar.gz";
    hash = "sha256-3Rb7HWe/q3mnL16DkHNcSePo5wtJRaFasfgd23hlj7M=";
  };

  patchDir = "${nixpkgsPath}/pkgs/os-specific/linux/minimal-bootstrap/gnumake";
  patches = [
    "${patchDir}/0001-No-impure-bin-sh.patch"
    "${patchDir}/0002-remove-impure-dirs.patch"
  ];
in
bash.runCommand "${pname}-${version}"
  {
    inherit pname version meta;

    nativeBuildInputs = [
      tinycc.compiler
      gnumakeBoot
      gnupatch
      gnused
      gnugrep
      gawk
      gnutar
      gzip
    ];

    passthru.tests.get-version =
      result:
      bash.runCommand "${pname}-get-version-${version}" { } ''
        ${result}/bin/make --version
        mkdir $out
      '';
  }
  ''
    tar xzf ${src}
    cd make-${version}

    ${lib.concatMapStringsSep "\n" (f: "patch -Np1 -i ${f}") patches}
    touch aclocal.m4 configure Makefile.in doc/Makefile.in lib/Makefile.in

    export CC="tcc -B ${tinycc.libs}/lib"
    export LD=tcc
    bash ./configure \
      --prefix=$out \
      --build=${buildPlatform.config} \
      --host=${hostPlatform.config} \
      --disable-dependency-tracking

    make AR="tcc -ar"
    make install
  ''
