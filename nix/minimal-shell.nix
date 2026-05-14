{
  lib,
  stdenvNoCC,
  busybox,
  removeReferencesTo,
}:

stdenvNoCC.mkDerivation {
  pname = "bootstrap-minimal-shell";
  version = "0.1";

  dontUnpack = true;
  nativeBuildInputs = [ removeReferencesTo ];

  installPhase = ''
    runHook preInstall
    install -Dm555 ${busybox}/bin/busybox $out/bin/sh
    runHook postInstall
  '';

  postFixup = ''
    remove-references-to -t ${busybox} $out/bin/sh
  '';

  meta = {
    description = "Minimal explicit POSIX shell for bootstrap Nix builders";
    platforms = lib.platforms.linux;
    license = busybox.meta.license;
  };
}
