{
  stdenv,
  lib,
  minimalBootstrap,
}:

stdenv.mkDerivation {
  pname = "m2-mesoplanet-gcc";
  version = "1.9.1";

  src = minimalBootstrap.stage0-posix.src;

  buildPhase = ''
    runHook preBuild

    cd M2-Mesoplanet
    $CC -D_GNU_SOURCE -O2 -std=c99 \
      -Wall -Wextra -Wno-unused-parameter \
      -I. \
      ../M2libc/bootstrappable.c \
      cc_reader.c \
      cc_core.c \
      cc_macro.c \
      cc_env.c \
      cc_spawn.c \
      cc.c \
      cc_globals.c \
      -o M2-Mesoplanet

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 M2-Mesoplanet "$out/bin/M2-Mesoplanet"
    runHook postInstall
  '';

  meta = {
    description = "M2-Mesoplanet compiled by the normal GCC toolchain for fast bootstrap debugging";
    homepage = "https://github.com/oriansj/stage0-posix";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
