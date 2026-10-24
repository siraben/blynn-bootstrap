# Tests

Keep gates focused on the bootstrap rather than exhaustive compiler contracts:

- `scripts/hcc-compiler-smoke.sh` preprocesses and parses two small inputs and
  checks that the M1 emitter runs when building HCC.
- `tests.smoke.m1*` and `tests.host.ghc.native.smoke.m1*` run six executable
  cases covering returns, control flow, aggregates, scope, integer widths, and
  the pointer operations needed by bootstrap qsort.
- `tests.precisely.dialect` checks the Blynn Haskell syntax HCC relies on.
- `tests.tinyccM1.native-vs-faithful` compares native and faithful M1 output.
- `tinycc.*` builds exercise real TinyCC self-hosting and its fixpoint; CI keeps
  the faithful debug and stage0 bootstrap paths as end-to-end gates.

Golden snapshots, MesCC scaffold tests, TinyCC statistics, and standalone
support-I/O contracts are deliberately not maintained here.
