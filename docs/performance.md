# Measuring bootstrap performance

Use the faithful M2 build to measure bootstrap cost, and the GHC profiling
build to find work worth investigating. Their timings and heap sizes are not
interchangeable: on amd64, for example, Blynn graph words are 32 bits with
host GCC and 64 bits with M2.

## Time the bootstrap stages

In `nix develop .#bench`, run:

```sh
scripts/bench-faithful-chain.sh "$PWD" baseline /tmp/blynn-bench tinycc.m2.precisely.m2
```

The harness realizes inputs before timing, then rebuilds selected stages
serially with substitution disabled and Nix output comparison enabled. It
records the revision, commands, logs and per-stage wall times. It excludes
downloads and the initial stage0 build. Run baseline/candidate/candidate/baseline
on the same quiet host. With a Nix daemon, GNU `time` measures the client's
CPU and RSS, not the builder's; measure the compiler directly for those.

## Measure HCC directly

Use the same expanded input for both revisions. The bootstrap passes
`--from-hcpp` because `hcpp` has already performed line splicing and comment
handling. Omit the flag for raw C.

```sh
input=$(nix build --no-link --print-out-paths .#tinycc.m1.host.ghc.native)
src="$input/share/tinycc-hcc-m1/tcc-expanded.c"
hcc=$(nix build --no-link --print-out-paths .#hcc.m2.precisely.m2)
time_bin=$(type -P time)  # GNU time in the bench shell
"$time_bin" -f 'user=%U system=%S maxrss_KiB=%M' \
  "$hcc/bin/hcc1" --from-hcpp --m1-ir -o tcc.ir "$src"
```

Compare IR bytes as well as CPU and peak RSS. For GHC/M2 output parity, run
`nix build --no-link .#tests.tinyccM1.native-vs-faithful`. For the default
raw-source path, `scripts/hcc-memory-bench.sh` reports elapsed time, peak RSS
and an IR hash; `GHC_RTS_STATS=1` adds RTS statistics for supported GHC builds.

## Attribute CPU, allocation and live memory

With `src` set as above, run the GHC profiles separately:

```sh
prof=$(nix build --no-link --print-out-paths .#hcc.profile.host.ghc.native)
"$prof/bin/hcc1" --from-hcpp --m1-ir -o time.ir "$src" +RTS -p -s -RTS
"$prof/bin/hcc1" --from-hcpp --m1-ir -o heap.ir "$src" +RTS -hd -i0.5 -RTS
```

`hcc1.prof` attributes CPU ticks and allocation to cost centres. `hcc1.hp`
samples the live heap by closure description: list cells include token and
AST lists as well as strings. Neither profile describes the M2 process's
peak RSS. Do not pass GHC RTS flags to Blynn binaries.

The Blynn runtime copies the live graph between two survivor regions. Peak
RSS is roughly `(2 * live + nursery) * word size` plus the touched C stack.
`hcc.m2.precisely.m2Lowmem` reduces both `TOP` and the nursery limit
(`HCC_RTS_ADAPTIVE_MAJOR_WORDS`); `hcc.m2.precisely.gccLowmem` lowers the
GC trigger. Matching `tinycc.*` targets are available. A smaller nursery can
increase collection work, and a smaller heap may not fit larger inputs.
