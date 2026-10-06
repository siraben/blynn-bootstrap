# Host-built grammar debug route (amd64 Linux)

```sh
nix flake check
bash tests/m2-grammar/provenance.sh
# Explicit heavy endpoint: version, stage2/stage3 executable fixpoint, execution.
nix build .#tinycc.ghc.precisely.grammar-gcc-debug
```

Routine checks cover:
- `m2-grammar-debug`: fork/GCC execution parity for `semantics.c` and six
  complementary upstream cases, plus the fork's non-ISO comma extension.
  All postfix, array-decay, signed pointer-difference, short-circuit and
  shorter include-path fork-fix regressions remain. Wrapper tests cover spaces,
  repeated files, option forms, empty PATH, invalid input, destination
  preservation and cleanup; core and full libc are both exercised.
- `tests.grammar-debug.sources`: real HCC C is compiled verbatim, the debug
  generator emits TOP/external allocation, and ordinary/default TOP output
  remains byte-identical to the original generator. #31 owns the TOP matrix.
- `tests.grammar-debug.tinycc-parity`: all nine TinyCC/support C, HCCIR and M1
  artifacts match actual faithful HCC. Native/faithful parity has its own gate.

The fork-built HCC already runs compiler smoke tests. Separate grammar golden
and CPU diagnostic targets were removed as redundant with smoke/parity; full
TinyCC self-hosting remains an explicit feature target, not a routine check.
CI also audits recursive derivation inputs: default/faithful outputs must not
acquire host-M2/fork dependencies, and grammar HCC must use the isolated
GHC generator and fork rather than faithful crossly C.

`m2.planet.grammar-gcc-debug` and `hcc.ghc.precisely.grammar-gcc-debug` remain
independently buildable. This host-GCC/host-GHC route uses the byte-addressed
RTSPrecisely runtime and source-generated allocator configuration. It is not
seed-only, does not build the Blynn ladder, and leaves faithful/portable and
old `gccm2` paths unchanged. No full C-conformance or downstream GCC claim.
