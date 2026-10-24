# Tests

Keep gates focused on the bootstrap rather than exhaustive compiler contracts:

- `scripts/hcc-compiler-smoke.sh` preprocesses and parses two small inputs and
  checks that the M1 emitter runs when building HCC.
- `tests.smoke.m1*` and `tests.host.ghc.native.smoke.m1*` run ten executable
  cases covering returns, control flow, aggregates, scope, integer widths,
  bootstrap qsort pointers, and four focused compiler regressions from master.
- `tests.host.ghc.native.mescc` keeps the fast-native MesCC scaffold checks
  on amd64 and AArch64.
- `tests.precisely.dialect` checks the Blynn Haskell syntax HCC relies on.
- `nix flake check` retains the bootstrap tool/source-selection shell checks.
- `tests.portable.tinycc-selfhost` checks the portable TinyCC bootstrap fixpoint.
- `tests.tinyccM1.native-vs-faithful` compares native and faithful output;
  `tests.tinyccM1.native-vs-blynn-gcc` covers the Blynn/GCC debug path.
- `tinycc.*` builds exercise real TinyCC self-hosting and its fixpoint; CI keeps
  the faithful debug and stage0 bootstrap paths as end-to-end gates.

Golden snapshots and TinyCC statistics are deliberately not maintained here.
