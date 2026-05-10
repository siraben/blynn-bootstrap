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

  patchGeneratedTop = file: top: ''
    substituteInPlace ${file} \
      --replace-fail 'enum{TOP=16777216};' 'enum{TOP=${toString top}};'
  '';
}
