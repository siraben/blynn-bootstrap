# Tests

```sh
nix flake check
nix build .#tests.smoke.m1 .#tests.mescc
nix build .#tests.tinyccM1.native-vs-faithful
nix build .#tinycc.m2.precisely.m2
```

- `nix flake check` runs HCC golden-output tests with M2-built HCC and
  shell regression tests for explicit toolchain/source selection and
  mandatory seed-answer checks. The shell tests use fixtures, not real
  seed builds; they also check missing answers, corrupted output, a missing
  hasher, and invalid local source overrides.
- `checks.blynn-top` (also `tests.precisely.top`) exercises the actual
  `crossly_up`, `crossly1`, seed/GCC Precisely, and GHC debug compilers: default
  and non-default TOP enums, invalid-option failures, and seed-M2 compilation
  and execution of generated probes. It runs portable HCC C generation with
  distinct HCPP/HCC1 sizes, checks that only the TOP line changes, rejects late
  binary-stage overrides, and smoke-tests the differently sized M2-built HCC.
- `tests.smoke.m1` compiles and executes C fixtures with M2-built HCC.
  Architecture-suffixed targets cover i386, AArch64, and RISC-V; cross-target
  execution uses QEMU. `tests.mescc` runs the selected MesCC scaffold cases.
- `tests.tinyccM1.native-vs-faithful` compares preprocessed C, IR, and M1 for
  TinyCC and its support code between GHC-built and stage0/M2-built HCC.
  It does not substitute the GCC backend for the M2 backend.
- `tests.portable.tinycc-selfhost` runs the portable TinyCC script with
  M2-built HCC, checks stage2/stage3 equality, and runs its compiled output.
- `tinycc.m2.precisely.m2` checks complete TinyCC stage2/stage3 binary
  equality, actual version output, and programs compiled by the rebuilt
  compiler. This covers self-compilation, not full C conformance.

For faster development, use `tests.host.ghc.native.smoke.m1`,
`tests.host.ghc.native.mescc`, and `tests.precisely.dialect`.
`tests.tinyccM1.native-vs-blynn-gcc` compares against the stage0-built Blynn
compiler with **GCC-built HCC**, rather than the M2 executable.
`tests.hcc.tinycc-tests2-stat` collects non-gating compatibility statistics;
a successful statistics build does not mean every TinyCC test passed.

`sh scripts/check-hcc-ir-opcodes.sh` compares the Haskell emitter's numeric
opcodes with the C backend constants. Compiler smoke tests also run it when
the source tree and awk are available.

Without Nix, run the tool-selection regression tests with:

```sh
sh tests/bootstrap-tools.sh
sh tests/prepare-upstreams.sh
```

Run `TINYCC_SELFHOST=1 scripts/bootstrap-blynn.sh` on amd64 for the portable
seed build, TinyCC fixpoint, and rebuilt-compiler execution check. Neither
output equality nor self-compilation establishes a complete trust proof.
