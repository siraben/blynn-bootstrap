{
  stdenvNoCC,
  lib,
  minimalBootstrap,
  generatedC,
  hccSrc,
  repoSrc,
  m2libcSrc,
  riscv64Binutils,
  bootstrapShell,
}:

let
  nixLib = import ./lib.nix { inherit lib; };
in
stdenvNoCC.mkDerivation (
  {
    pname = "jslinux-hcc-riscv64-checkpoint";
    version = nixLib.bootstrapVersion;
  }
  // nixLib.scriptOnly
  // nixLib.skipFixup
  // {
    nativeBuildInputs = [
      minimalBootstrap.stage0-posix.mescc-tools
      riscv64Binutils
    ];

    buildPhase = ''
      runHook preBuild

      ulimit -s unlimited

      mkdir -p source out
      cp ${generatedC}/share/${generatedC.pname}/hcpp-blynn.c source/hcpp-blynn.c
      cp ${generatedC}/share/${generatedC.pname}/hcc1-blynn.c source/hcc1-blynn.c

      BOOTSTRAP_LOG_NAME=jslinux-hcc-checkpoint \
      BOOTSTRAP_LIB=${repoSrc}/scripts/lib/bootstrap.sh \
      HCC_BLYNN_C_DIR="$PWD/source" \
      HCC_DIR=${hccSrc} \
      M2LIBC_PATH=${m2libcSrc} \
      M2_ARCH=riscv64 \
      M2_OS=Linux \
      HCC_C_BACKEND=m2 \
      HCPP_TOP=67108864 \
      HCC1_TOP=67108864 \
      HCC_RTS_ADAPTIVE_MAJOR_WORDS=33554432 \
      OUT_DIR="$PWD/out" \
        ${bootstrapShell}/bin/sh ${repoSrc}/scripts/hcc-blynn-bin.sh

      mkdir -p out/support-objects
      ${riscv64Binutils}/bin/${riscv64Binutils.targetPrefix or ""}as \
        -o out/support-objects/crt1.o.tmp \
        ${repoSrc}/hcc/support/tcc-riscv64-crt1.s
      ${riscv64Binutils}/bin/${riscv64Binutils.targetPrefix or ""}objcopy \
        --remove-section=.data \
        --remove-section=.bss \
        out/support-objects/crt1.o.tmp \
        out/support-objects/crt1.o
      rm out/support-objects/crt1.o.tmp

      ${riscv64Binutils}/bin/${riscv64Binutils.targetPrefix or ""}as \
        -o out/support-objects/riscv64-syscalls.o.tmp \
        ${repoSrc}/hcc/support/tcc-riscv64-syscalls.s
      ${riscv64Binutils}/bin/${riscv64Binutils.targetPrefix or ""}objcopy \
        --remove-section=.data \
        --remove-section=.bss \
        out/support-objects/riscv64-syscalls.o.tmp \
        out/support-objects/riscv64-syscalls.o
      rm out/support-objects/riscv64-syscalls.o.tmp

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -R out/. "$out/"
      chmod 555 "$out/bin/hcpp" "$out/bin/hcc1" "$out/bin/hcc-m1"
      (
        cd "$out"
        sha256sum \
          bin/hcpp \
          bin/hcc1 \
          bin/hcc-m1 \
          support-objects/crt1.o \
          support-objects/riscv64-syscalls.o \
          > SHA256SUMS
      )

      runHook postInstall
    '';

    meta = {
      description = "RISC-V HCC checkpoint for the JSLinux TinyCC demo";
      platforms = lib.platforms.linux;
      license = lib.licenses.gpl3Only;
    };
  }
)
