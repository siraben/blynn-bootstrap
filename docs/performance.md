# Performance tools

Measure the compiler path being changed. Host GHC, host GCC, and M2 builds
have different runtimes and integer representations. In particular, Blynn's
`unsigned` graph words are 32 bits with host GCC and 64 bits with M2 on
amd64. A timing difference between those builds is not just codegen cost.

## Bootstrap stages

```sh
scripts/bench-faithful-chain.sh "$PWD" baseline /tmp/blynn-bench
```

The harness requires Nix, jq, ripgrep, and GNU `time` (available in
`nix develop .#bench`). It realizes build inputs even when stage outputs
are already cached, outside the timed region, then rebuilds the
selected Blynn/HCC/TinyCC derivations serially with substitution disabled
and Nix's output comparison enabled. It records the revision, commands,
logs, and timings, including the separate Mes source-patching stage. It does
not time the initial stage0 build or downloads. With a Nix daemon, GNU
`time`'s CPU and RSS fields describe the client, not the builder; use direct
compiler or builder runs for those metrics.

### Direct argument reads, sized zero fills, and streaming M1 data

On `compute` (amd64), the 44 timed derivations for `tinycc.m2.precisely.m2`
were rebuilt in master/stack/stack/master order. Wall seconds:

| Revision | Blynn + its source prep | HCC construction | Mes prep | TinyCC bootstrap | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| `61798ce` | 473.12 | 118.72 | 1.26 | 123.62 | 716.72 |
| `e7a9fbf` | 455.93 | 118.95 | 1.01 | 122.72 | 698.61 |
| `e7a9fbf` | 456.79 | 118.91 | 1.12 | 122.21 | 699.03 |
| `61798ce` | 472.36 | 118.45 | 1.02 | 123.02 | 714.85 |

The stack saved 16.97 s on average (2.37%). Most of the difference was in
Blynn, not in the final TinyCC build. These are stack measurements, not
individual commit speedups. In a separate amd64 output comparison, streaming
M1 data reduced `tcc.M1` from 5,468,207 to 4,568,702 bytes without changing
the linked executable.

## HCC memory and runtime

```sh
input=$(nix build --no-link --print-out-paths .#tinycc.m1.host.ghc.native)
hcc=$(nix build --no-link --print-out-paths .#hcc.m2.precisely.m2)
scripts/hcc-memory-bench.sh header
scripts/hcc-memory-bench.sh "$hcc/bin/hcc1" \
  "$input/share/tinycc-hcc-m1/tcc-expanded.c" m2
```

The harness requires GNU `time` (`GNUTIME` can select it). It reports wall
time, peak RSS, and an IR hash. Set `GHC_RTS_STATS=1` to include allocation
and residency statistics for a GHC-built binary with RTS statistics enabled.
Do not pass GHC RTS flags to M2/Blynn binaries.

`hcc.m2.precisely.m2Lowmem` reduces both `TOP` and
`HCC_RTS_ADAPTIVE_MAJOR_WORDS`; `hcc.m2.precisely.gccLowmem` lowers the GC
trigger for the GCC-built debug path. Matching `tinycc.*` targets are
available. Lower thresholds trade more collection work for less allocation
slack; a smaller heap can also run out of space on larger inputs.

`hcpp` and `hcc1` allocate in a nursery of at most
`HCC_RTS_ADAPTIVE_MAJOR_WORDS` words and copy the live graph between two
survivor regions. Peak RSS is about `(2 * live + nursery) * word size` plus
the touched C stack, so separate these parts when comparing memory numbers.

Compare output bytes as well as timings, and alternate repeated baseline
and candidate runs. Wall time of an M2 build varies between runs; pin a run
to one core and count instructions to compare small changes. Use `tests.tinyccM1.native-vs-faithful` for GHC/M2
output parity. Historical measurements and experiments are in Git history,
not performance guarantees for the current tree.
