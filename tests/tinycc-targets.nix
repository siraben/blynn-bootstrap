{ lib }:
let
  recipe =
    target:
    import ../nix/tinycc-boot-hcc.nix {
      inherit lib target;
      stdenvNoCC.mkDerivation = args: args;
      fetchgit = _: "/tinycc-source";
      hcc = "/hcc";
      binutils = "/binutils";
      diffutils = "/diffutils";
      gnugrep = "/gnugrep";
      minimalBootstrap.stage0-posix = {
        mescc-tools = "/mescc-tools";
        m2libcArch = "amd64";
        m2libcOS = "Linux";
      };
      qemu = "/qemu";
      mesLibc = "/mes-libc";
      m2libc = "/m2libc";
    };
  phase = target: (recipe target).buildPhase;
  rejects = target: !(builtins.tryEval (phase target)).success;
in
assert phase "amd64" == phase "x86_64";
assert phase "aarch64" == phase "arm64";
assert lib.hasInfix "TCC_TARGET_RISCV64" (phase "riscv64");
assert lib.hasInfix "qemu-riscv64" (phase "riscv64");
assert builtins.all rejects [
  "bogus"
  "i386"
  "i686"
  "x86"
  ""
];
true
