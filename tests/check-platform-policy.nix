{ lib, system, checks, tests, publicChecks }:
let
  # Filtering must not inspect unsupported or non-gating derivations.
  selected = import ../nix/test-checks.nix {
    inherit lib system;
    registry = {
      native = { systems = [ system ]; gating = true; drv = "native"; };
      unsupported = { systems = [ ]; gating = true; drv = throw "unsupported"; };
      statistics = { systems = [ system ]; gating = false; drv = throw "non-gating"; };
    };
  };
in
assert selected == { native = "native"; };
assert lib.isDerivation publicChecks.bootstrap-tools;
assert !(builtins.elem system [ "x86_64-linux" "aarch64-linux" ]) || (
  publicChecks.hcc-golden.drvPath == tests.hcc.golden.drvPath
  && publicChecks.hcc-golden.drvPath == publicChecks."hcc.golden".drvPath
  && checks ? "smoke.m1-aarch64"
  && checks ? "host.ghc.native.smoke.m1-aarch64"
);
# Public checks remain the real legacy tests, not replacement derivations.
assert lib.all (name: checks.${name}.drvPath ==
  (lib.attrByPath (lib.splitString "." name) null tests).drvPath
) (builtins.attrNames checks);
true
