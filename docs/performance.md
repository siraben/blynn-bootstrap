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

## Identifier costs on expanded TinyCC

On amd64 at `36179f2`, one direct `hcc.m2.precisely.m2` run of `hcc1
--m1-ir` on `tcc-expanded.c` took 93.37 user + 2.91 system seconds and
peaked at 851 MiB RSS. This is the compile stage, not `hcpp` or the M1
assembler. To attribute costs rather than just time the whole executable,
use the GHC profile build (with the GHC shutdown fix on this branch):

```sh
prof=$(nix build --no-link --print-out-paths .#hcc.profile.host.ghc.native)
input=$(nix build --no-link --print-out-paths .#tinycc.m1.host.ghc.native)
src="$input/share/tinycc-hcc-m1/tcc-expanded.c"
"$prof/bin/hcc1" --m1-ir -o time.ir "$src" +RTS -p -s -RTS  # hcc1.prof
"$prof/bin/hcc1" --m1-ir -o heap.ir "$src" +RTS -hd -i0.5 -RTS  # hcc1.hp
```

* **CPU and allocation:** `SymbolTable.hashFrom` alone took 10.4% of GHC
  profile ticks and 13.5% of attributed allocation. A tree node already
  stores its hash; it is the *query* spelling that gets walked on each
  operation. String comparison itself took 1.2%. Other costs are not all
  string costs: parser and lowering monad bind continuations took 5.5% and
  5.1% of ticks respectively.
* **Live memory:** at the largest sampled `-hd` census (75.9 MB excluding
  profiling overhead), list cells accounted for 36.2 MB, `SrcPos` 9.2 MB,
  and `Span` and `Token` 4.6 MB each. List cells include token and AST lists,
  not just `String`; 36.2 MB is **not** the saving available from packing
  text. The GHC samples are not a breakdown of the M2 process's RSS.

First experiment: carry a spelling and reusable hash only for identifiers
that pass through repeated symbol lookups. Keep the spelling for diagnostics
and compare it on hash ties. This can remove repeated linear walks without
adding a runtime primitive, but an extra field per occurrence may increase
residency. Compare CPU, RSS and IR bytes on the M2 path before adopting it.
For memory, investigate token span lifetime separately. A packed source
buffer would help a different problem: slices can avoid copying lexemes but
can also keep the entire input alive, and still require hashing on lookup.

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
