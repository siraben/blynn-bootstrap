{
  lib,
  buildPlatform,
  hostPlatform,
  fetchurl,
  bash,
  gnumake,
  tinycc,
  gnused,
  gnugrep,
  gnutar,
  gzip,
}:

let
  common = import ./common.nix { inherit lib; };
  pname = "gnused";
  version = "4.2";
  meta = common.mkMeta {
    description = "GNU sed, a batch stream editor";
    homepage = "https://www.gnu.org/software/sed/";
    mainProgram = "sed";
  };

  src = fetchurl {
    url = "mirror://gnu/sed/sed-${version}.tar.gz";
    hash = "sha256-20XNY/0BDmUFN9ZdXfznaJplJ0UjZgbl5ceCk3Jn2YM=";
  };

  # Ancient config.sub rejects musl-flavoured 4-component tuples.
  fakeBuildPlatform = lib.strings.removeSuffix "-musl" buildPlatform.config;
  fakeHostPlatform = lib.strings.removeSuffix "-musl" hostPlatform.config;
in
bash.runCommand "${pname}-${version}"
  {
    inherit pname version meta;

    nativeBuildInputs = [
      gnumake
      tinycc.compiler
      gnused
      gnugrep
      gnutar
      gzip
    ];

    passthru.tests.get-version = common.mkVersionTest bash pname version "sed";
  }
  ''
    tar xzf ${src}
    cd sed-${version}

    export CC="tcc -B ${tinycc.libs}/lib"
    export LD=tcc
    ./configure \
      --build=${fakeBuildPlatform} \
      --host=${fakeHostPlatform} \
      --disable-shared \
      --disable-nls \
      --disable-dependency-tracking \
      --prefix=$out

    # Parallel tcc-musl builds have been unstable here.
    make AR="tcc -ar"

    make install
  ''
