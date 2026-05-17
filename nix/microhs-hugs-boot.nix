{
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  hugs,
  patches,
  pname ? "microhs-hugs-boot",
}:

stdenvNoCC.mkDerivation {
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

  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    rm -rf generated
  '';

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/microhs-hugs"
    s="$out/share/microhs-hugs/src"
    cp -r . "$s"

    makeWrapper ${hugs}/bin/runhugs "$out/bin/mhs" \
      --add-flags "'+P$s/hugs:$s/src:$s/paths:{Hugs}/packages/*:hugs/obj' -98 +o +w -h100m '$s/hugs/Main.hs'"

    runHook postInstall
  '';

  passthru = {
    isMhs = true;
    usesHugs = true;
  };
}
