{ lib }:

rec {
  bootstrapVersion = "0-unstable-2026-05-06";

  skipPatchConfigure = {
    dontPatch = true;
    dontConfigure = true;
    dontUpdateAutotoolsGnuConfigScripts = true;
  };

  skipFixup = {
    dontFixup = true;
    dontPatchELF = true;
  };

  scriptOnly = {
    dontUnpack = true;
  }
  // skipPatchConfigure
  // skipFixup;

  shellHelpers = { name }: ''
    log_step() {
      printf '${name}: %s\n' "$1"
    }

    log_file() {
      log_step "FILE  $1"
    }
  '';
}
