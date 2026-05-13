{
  stdenvNoCC,
  lib,
  fetchgit,
  python3,
  hcc,
  minimalBootstrap,
  m2libc,
  support,
  target ? "amd64",
  pname ? "hcc-tinycc-tests2-stat",
}:

let
  version = "unstable-2025-12-03";
  rev = "cb41cbfe717e4c00d7bb70035cda5ee5f0ff9341";
  src = fetchgit {
    url = "https://repo.or.cz/tinycc.git";
    inherit rev;
    hash = "sha256-LgYeX6Q80Z6VNJ7iPk46fPpEr/dEAezqvR6jQddSsxI=";
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;
  dontUpdateAutotoolsGnuConfigScripts = true;

  nativeBuildInputs = [
    minimalBootstrap.stage0-posix.mescc-tools
    python3
  ];

  checkPhase = ''
    runHook preCheck
    python3 ${../scripts/hcc-tinycc-tests2-stat.py} \
      --hcpp ${hcc}/bin/hcpp \
      --hcc1 ${hcc}/bin/hcc1 \
      --hcc-m1 ${hcc}/bin/hcc-m1 \
      --target ${target} \
      --m2libc ${m2libc} \
      --support-dir ${support} \
      --source-dir tests/tests2 \
      --work-dir "$PWD/hcc-tinycc-tests2-work" \
      --summary "$PWD/hcc-tinycc-tests2-summary.txt" \
      --fail-dir "$PWD/hcc-tinycc-tests2-failures"
    runHook postCheck
  '';

  doCheck = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 hcc-tinycc-tests2-summary.txt "$out/share/hcc-tinycc-tests2-stat/summary.txt"
    mkdir -p "$out/share/hcc-tinycc-tests2-stat/failures"
    cp -R hcc-tinycc-tests2-failures/. "$out/share/hcc-tinycc-tests2-stat/failures/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Non-gating TinyCC tests2 statistics with HCC as the C compiler";
    homepage = "https://repo.or.cz/w/tinycc.git";
    license = licenses.lgpl21Only;
    platforms = platforms.linux;
  };
}
