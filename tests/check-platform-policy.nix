{ lib, system, checks, tests, publicChecks }:
let
  select = registry: system: import ../nix/test-checks.nix {
    inherit lib registry system;
  };
  # Poison values prove filtering happens before derivation inspection; do not
  # replace this with tryEval, which could silently discard a broken real check.
  fixture = {
    native = { systems = [ "aarch64-linux" ]; gating = true; drv = "native"; };
    unsupported = {
      systems = [ "x86_64-linux" ]; gating = true;
      drv = throw "forced an unsupported derivation";
    };
    statistics = {
      systems = [ "aarch64-linux" ]; gating = false;
      drv = throw "forced the non-gating collector";
    };
  };
  linux = [
    "host.ghc.native.mescc"
    "host.ghc.native.smoke.m1"
    "host.ghc.native.smoke.m1-aarch64"
    "host.ghc.native.smoke.m1-riscv64"
    "host.ghc.native.tinycc-riscv64"
    "precisely.dialect"
    "smoke.m1-aarch64"
    "smoke.m1-riscv64"
    "tinyccM1.native-vs-blynn-gcc"
    "tinyccM1.native-vs-faithful"
  ];
  x86 = [
    "host.ghc.native.smoke.m1-i386"
    "mescc"
    "portable.tinycc-selfhost"
    "smoke.m1"
    "smoke.m1-i386"
  ];
  expected = if system == "x86_64-linux" then linux ++ x86
    else if system == "aarch64-linux" then linux else [ ];
  expectedPublic = expected ++ [ "bootstrap-tools" "check-platform-policy" ];
in
assert select fixture "aarch64-linux" == { native = "native"; };
assert select fixture "x86_64-darwin" == { };
assert builtins.attrNames checks == lib.sort builtins.lessThan expected;
assert builtins.attrNames publicChecks == lib.sort builtins.lessThan expectedPublic;
# Protect the pre-existing public shell checks independently of test metadata.
assert lib.isDerivation publicChecks.bootstrap-tools;
assert builtins.isString publicChecks.bootstrap-tools.drvPath;
# Force actual derivations, not just names. Also ensure each flattened check is
# the original legacy package target, rather than a replacement/no-op test.
assert lib.all (name:
  lib.isDerivation checks.${name}
  && checks.${name}.drvPath == (lib.attrByPath (lib.splitString "." name)
    (throw "missing legacy test ${name}") tests).drvPath
) expected;
true
