{
  stdenv,
  lib,
  ghc,
  src,
  pname ? "hcc-host-ghc-native",
  extraGhcFlags ? [ ],
  extraCFlags ? [ ],
  description ? "GHC-backed development build of the hcc bootstrap C compiler",
}:

let
  nixLib = import ./lib.nix { inherit lib; };
  ghcFlags = lib.concatStringsSep " " (
    [
      "-O0"
      "-fno-cse"
      "-fno-enable-rewrite-rules"
      "-fno-full-laziness"
      "-fno-specialise"
      "-fno-state-hack"
      "-fno-strictness"
      "-fno-worker-wrapper"
      "-Wall"
      "-Werror"
      "-XNoImplicitPrelude"
      "-XForeignFunctionInterface"
    ]
    ++ extraGhcFlags
  );
  cFlags = lib.concatStringsSep " " (
    [
      "-O0"
      "-U_FORTIFY_SOURCE"
      "-Wall"
      "-Werror"
    ]
    ++ extraCFlags
  );
  ghcCFlags = lib.concatStringsSep " " (
    map (flag: "-optc${flag}") (
      [
        "-O0"
        "-U_FORTIFY_SOURCE"
      ]
      ++ extraCFlags
    )
  );
in
stdenv.mkDerivation (
  {
    inherit pname;
    version = nixLib.bootstrapVersion;

    inherit src;
  }
  // nixLib.skipPatchConfigure
  // {

    nativeBuildInputs = [ ghc ];
    hardeningDisable = [ "fortify" ];

    buildPhase = ''
      runHook preBuild
      mkdir -p build/hcpp build/hcc1
      ghc ${ghcFlags} ${ghcCFlags} \
        -isrc -isrc/Hcc src/MainCpp.hs cbits/hcc_runtime.c -outputdir build/hcpp -o hcpp
      ghc ${ghcFlags} ${ghcCFlags} \
        -isrc -isrc/Hcc src/MainCc1.hs cbits/hcc_runtime.c -outputdir build/hcc1 -o hcc1
      cc ${cFlags} cbits/hcc_m1.c -o hcc-m1
      ./hcpp ${../tests/hcc/pp-smoke.c} > pp-smoke.i
      ./hcc1 --check pp-smoke.i
      ./hcpp ${../tests/hcc/parse-smoke.c} > parse-smoke.i
      ./hcc1 --check parse-smoke.i
      ./hcc1 --m1-ir -o smoke.hccir parse-smoke.i
      ./hcc-m1 smoke.hccir smoke.M1
      expect_file_contains() {
        pattern="$1"
        file="$2"
        found=0
        while IFS= read -r line; do
          case "$line" in
            *"$pattern"*) found=1; break ;;
          esac
        done < "$file"
        if test "$found" != 1; then
          echo "$file: expected diagnostic containing: $pattern" >&2
          exit 1
        fi
      }
      expect_hcc1_fail() {
        name="$1"
        pattern="$2"
        src="$3"
        ./hcpp "$src" > "$name.i"
        set +e
        ./hcc1 --m1-ir -o "$name.hccir" "$name.i" 2> "$name.err"
        code="$?"
        set -e
        if test "$code" = 0; then
          echo "$name: expected hcc1 failure" >&2
          exit 1
        fi
        expect_file_contains "$pattern" "$name.err"
      }
      expect_hcc1_fail unknown-identifier "unknown identifier: missing_global" ${../tests/hcc/diagnostics/unknown-identifier.c}
      expect_hcc1_fail unknown-global-initializer "unknown constant: missing_global" ${../tests/hcc/diagnostics/unknown-global-initializer.c}
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm555 hcpp $out/bin/hcpp
      install -Dm555 hcc1 $out/bin/hcc1
      install -Dm555 hcc-m1 $out/bin/hcc-m1
      runHook postInstall
    '';

    meta = with lib; {
      inherit description;
      license = licenses.gpl3Only;
      platforms = platforms.linux;
    };
  }
)
