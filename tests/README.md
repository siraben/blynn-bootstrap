# Tests

```sh
nix flake check
nix build .#tests.smoke.m1 .#tests.mescc
nix build .#tests.tinyccM1.native-vs-faithful
nix build .#tinycc.m2.precisely.m2
```

- `nix flake check` runs the gating `tests.*` derivations supported by the
  host, using dotted check names (for example `checks.x86_64-linux."smoke.m1"`).
  `bootstrap-tools` also runs shell regressions for explicit toolchain/source
  selection and mandatory seed-answer checks. These use fixtures, not real
  seed builds; they cover missing answers, corrupted output, a missing hasher,
  and invalid local source overrides.
- Both x86_64 and AArch64 Linux include M2-built HCC golden tests;
  `hcc-golden` and `hcc.golden` alias the same derivation, built only once.
  On AArch64, native GHC smoke and its AArch64 alias also share a derivation.
  Both include M2/GHC AArch64 and RISC-V smoke tests, native GHC smoke/MesCC,
  dialect tests, RISC-V TinyCC via QEMU, and both TinyCC artifact comparisons.
  Golden/artifact comparisons execute host-built compilers, not emitted code.
- Only portable TinyCC selfhost and tests that directly execute amd64/i386
  output without a cross runner are x86_64-only (`smoke.m1`, `smoke.m1-i386`,
  `mescc`, and `host.ghc.native.smoke.m1-i386`). AArch64 smoke output runs
  natively or via QEMU; RISC-V smoke output always uses QEMU. Platform metadata
  is selected before evaluating derivations; `check-platform-policy` asserts
  legacy target identity, preservation of the shell/golden and ARM checks
  on both Linux systems, and lazy exclusion of unsupported/non-gating tests.
- Darwin exposes only shell regressions and the platform-policy assertions.
  The flake's existing default package/toolchain remains Linux-only, so a full
  `nix flake check --all-systems` is not supported. This does not claim Darwin
  compiler coverage.
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
`tests.hcc.tinycc-tests2-stat` collects non-gating compatibility statistics
and is deliberately excluded from flake checks; a successful statistics build
does not mean every TinyCC test passed. All existing `tests.*` package targets
remain available by their original names.

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
