{
  stdenvNoCC,
  lib,
  hcc,
  minimalBootstrap,
  m2libc,
  qemu,
  gnused,
}:
let
  nixLib = import ./lib.nix { inherit lib; };
  support = ../hcc/support;
in
stdenvNoCC.mkDerivation (
  nixLib.scriptOnly
  // {
    pname = "tcc-reduced-allocator-aarch64-test";
    version = nixLib.bootstrapVersion;
    nativeBuildInputs = [
      hcc
      minimalBootstrap.stage0-posix.mescc-tools
      qemu
      gnused
    ];
    buildPhase = ''
      # Exercise the shared C allocator, not the distinct M1 seed allocator.
      cat > allocator-prefix.c <<'EOF'
      long brk(void *addr);
      void _exit(int code);
      void *memset(void *ptr, int value, unsigned long count) {
        char *bytes = ptr;
        unsigned long i;
        for (i = 0; i < count; i = i + 1) bytes[i] = value;
        return ptr;
      }
      #include "tcc-reduced-allocator.h"
      EOF
      cat allocator-prefix.c ${../tests/hcc/tcc-reduced-allocator.c} > allocator.c
      hcpp -I ${support} allocator.c > allocator.i
      hcc1 --target aarch64 --m1-ir -o allocator.hccir allocator.i
      hcc-m1 --target aarch64 allocator.hccir allocator.M1
      # The shared C allocator owns exit; the startup file also aliases it.
      sed '/:FUNCTION_exit/,$d' ${support}/aarch64-start.M1 > start.M1
      cat >> start.M1 <<'EOF'
      :FUNCTION__exit
        SET_X8_TO_SYS_EXIT
        SYSCALL
      EOF
      M1 --architecture aarch64 --little-endian \
        -f ${m2libc}/aarch64/aarch64_defs.M1 \
        -f start.M1 -f allocator.M1 -f ${support}/aarch64-syscalls.M1 \
        --output allocator.hex2
      printf ':ELF_end\n' > end.hex2
      hex2 --architecture aarch64 --little-endian --base-address 0x00600000 \
        --file ${m2libc}/aarch64/ELF-aarch64.hex2 \
        --file allocator.hex2 --file end.hex2 --output allocator
      chmod 555 allocator
      qemu-aarch64 ./allocator
    '';
    installPhase = ''
      mkdir -p "$out"
      cp allocator allocator.i allocator.hccir allocator.M1 "$out/"
    '';
  }
)
