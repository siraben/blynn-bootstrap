{ stdenv, lib, src, bash, coreutils, mesccTools }:

stdenv.mkDerivation {
  pname = "m2-planet-grammar-gcc-debug";
  version = "ad19a2d";
  inherit src;
  # The grammar branch does not include this separately proposed lowering fix.
  # Without it, global/static postfix operations dereference values as addresses.
  patches = [
    ../patches/upstreams/m2-planet-grammar-postfix.patch
    ../patches/upstreams/m2-planet-grammar-expressions.patch
    ../patches/upstreams/m2-planet-grammar-includes.patch
  ];

  dontConfigure = true;
  dontUpdateAutotoolsGnuConfigScripts = true;

  buildPhase = ''
    runHook preBuild
    $CC -D_GNU_SOURCE -O2 -std=c99 -Wall -Wextra -Wno-unused-parameter \
      -I. M2libc/bootstrappable.c cc_reader.c cc_strings.c cc_types.c \
      cc_emit.c cc_core.c cc_macro.c cc.c cc_globals.c -o M2-Planet
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 M2-Planet "$out/libexec/M2-Planet"
    mkdir -p "$out/bin"
    substitute ${../scripts/m2-planet-grammar-gcc-debug.sh} \
      "$out/bin/m2-planet-grammar-gcc-debug" \
      --replace-fail '@bash@' '${bash}/bin/bash' \
      --replace-fail '@compiler@' "$out/libexec/M2-Planet" \
      --replace-fail '@libc@' '${src}/M2libc' \
      --replace-fail '@tools@' '${mesccTools}/bin' \
      --replace-fail '@coreutils@' '${coreutils}/bin'
    chmod 755 "$out/bin/m2-planet-grammar-gcc-debug"
    runHook postInstall
  '';

  meta = {
    description = "Host-GCC-built M2-Planet grammar experiment (not a bootstrap backend)";
    homepage = "https://github.com/siraben/M2-Planet";
    license = lib.licenses.gpl3Plus;
    # The executable-producing adapter is validated only for amd64 Linux.
    platforms = [ "x86_64-linux" ];
  };
}
