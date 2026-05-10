args@{
  stdenv,
  lib,
  ghc,
  src,
  ...
}:

import ./hcc-ghc.nix (
  args
  // {
    pname = "hcc-profile-host-ghc-native";
    extraGhcFlags = [
      "-prof"
      "-fprof-auto"
      "-rtsopts"
    ];
    description = "Profiling build of the GHC-backed hcc bootstrap C compiler";
  }
)
