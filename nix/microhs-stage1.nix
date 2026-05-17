{
  stdenv,
  fetchFromGitHub,
  microhsBoot,
  patches,
  pname ? "microhs-stage1-from-hugs-tcc-musl",
}:

stdenv.mkDerivation {
  inherit pname;
  version = "0.15.4.0";

  src = fetchFromGitHub {
    owner = "augustss";
    repo = "MicroHs";
    rev = "refs/tags/v0.15.4.0";
    fetchSubmodules = true;
    hash = "sha256-FUr2EA3zbmt2Tr2F8zT1wHnB8GDlUVb2W1fP4IqNd80=";
  };

  inherit patches;

  postPatch = ''
    rm -rf generated
  '';

  makeFlags = [ "PREFIX=${placeholder "out"}" ];
  installTargets = [
    "targets.conf"
    "oldinstall"
  ];

  buildPhase = ''
    runHook preBuild
    mkdir -p bin
    printf 'Building bin/mhs using ${microhsBoot}/bin/mhs\n'
    ${microhsBoot}/bin/mhs -l -imhs -isrc -ipaths MicroHs.Main -o bin/mhs
    runHook postBuild
  '';
}
