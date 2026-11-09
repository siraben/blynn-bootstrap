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
    # CCC adds a target record to HCCIR. Expect it explicitly rather than
    # stripping metadata from the compiler's actual output.
    cp -R ${testsSrc}/hcc/golden golden
    chmod -R u+w golden
    for expected in golden/expected/*.hccir; do
      sed -i '1aT amd64' "$expected"
    done
    sh golden/run.sh golden
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
