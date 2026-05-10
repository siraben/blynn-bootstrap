{
  lib,
  stdenvNoCC,
  pname,
  precisely,
  sourceBundle,
  shareName ? pname,
}:

let
  nixLib = import ./lib.nix { inherit lib; };
in
stdenvNoCC.mkDerivation (
  {
    inherit pname;
    version = nixLib.bootstrapVersion;
  }
  // nixLib.scriptOnly
  // {

    buildPhase = ''
      runHook preBuild

      log_step() {
        printf 'hcc-blynn-c: %s\n' "$1"
      }

      run_step_shell() {
        label="$1"
        command="$2"
        log_step "START $label"
        eval "$command"
        log_step "DONE  $label"
      }

      log_file() {
        file="$1"
        log_step "FILE  $file"
      }

      cp ${sourceBundle}/share/hcc-blynn-sources/hcpp-full.hs hcpp-full.hs
      cp ${sourceBundle}/share/hcc-blynn-sources/hcc1-full.hs hcc1-full.hs
      log_file hcpp-full.hs
      log_file hcc1-full.hs

      log_step "precisely_up translates concatenated Blynn-dialect Haskell to C; hcc1 is the long stage"
      run_step_shell "precisely_up hcpp-full.hs -> hcpp-blynn.c" "${precisely}/bin/precisely_up < hcpp-full.hs > hcpp-blynn.c"
      log_file hcpp-blynn.c
      run_step_shell "precisely_up hcc1-full.hs -> hcc1-blynn.c" "${precisely}/bin/precisely_up < hcc1-full.hs > hcc1-blynn.c"
      log_file hcc1-blynn.c

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm644 hcpp-blynn.c $out/share/${shareName}/hcpp-blynn.c
      install -Dm644 hcc1-blynn.c $out/share/${shareName}/hcc1-blynn.c
      install -Dm644 hcpp-full.hs $out/share/${shareName}/hcpp-full.hs
      install -Dm644 hcc1-full.hs $out/share/${shareName}/hcc1-full.hs
      runHook postInstall
    '';

    meta = {
      description = "Generated C for HCC from Blynn precisely";
      platforms = lib.platforms.linux;
      license = lib.licenses.gpl3Only;
    };
  }
)
