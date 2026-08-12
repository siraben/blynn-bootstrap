{ stdenvNoCC, cccAsHcc, coreutils, diffutils, gnused, cccSrc, testsSrc }:

stdenvNoCC.mkDerivation {
  pname = "ccc-golden-tests";
  version = "unstable";
  dontUnpack = true;
  nativeBuildInputs = [ cccAsHcc coreutils diffutils gnused ];

  buildPhase = ''
    runHook preBuild
    export HCPP=${cccAsHcc}/bin/hcpp
    export HCC1=${cccAsHcc}/bin/hcc1
    export HCC_M1=${cccAsHcc}/bin/hcc-m1
    sh ${testsSrc}/hcc/golden/run.sh ${testsSrc}/hcc/golden
    sh ${cccSrc}/tests/run-target-tests.sh "$HCPP" "$HCC1"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    echo "CCC golden and target tests passed" > "$out/result"
    runHook postInstall
  '';
}
