# HCC Optimization Log

Working metrics for improving HCC efficiency and modularity. The primary benchmark is the end-to-end TinyCC bootstrap path, with direct HCC-on-expanded-TCC measurements used to isolate compiler runtime and memory.

## Baseline: 2026-05-07

Repository state: `fca44e9 Install self-hosted hcc TinyCC`.

Haskell LOC:

```text
vendor/hcc/Main.hs       637
vendor/hcc/Hcc/*.hs    4991
total                  5628
```

Binary sizes:

```text
hcc-ghc/bin/hcc                  4,378,184 bytes
tinycc-boot-hcc/bin/tcc-hcc-stage1 2,767,218 bytes
tinycc-boot-hcc/bin/tcc            338,120 bytes
```

TinyCC bootstrap derivation:

```text
nix shell nixpkgs#time -c time -v nix build --rebuild --no-link .#tinycc-boot-hcc
wall: 11.51s
client max RSS: 42,732 KiB
```

Note: the Nix client timing is useful for wall-clock tracking, but builder RSS is not captured by this command because the daemon runs the build.

Direct HCC compile of the patched TinyCC source:

```text
hcc --expand-dump ... tcc.c > tcc-expanded.c
wall: 0.28s
max RSS: 80,424 KiB
tcc-expanded.c: 1,241,347 bytes

hcc -S -o tcc.M1 tcc-expanded.c
wall: 5.58s
max RSS: 260,368 KiB
tcc.M1: 508,341 lines, 14,903,462 bytes
```

Initial observations:

- `hcc -S` dominates the direct HCC workload.
- `Hcc.RegAlloc` stores allocations as a list. Codegen calls `lookupLocation` for nearly every operand, making temp lookup linear in the number of allocated temps.
- HCC is currently built by GHC without optimization flags.

## Pass 1: Map-backed allocation and optimized GHC build

Changes:

- Changed `Hcc.RegAlloc.Allocation` from a list of `(Temp, Location)` pairs to a strict `Map`.
- Stored the stack slot count directly in `Allocation`.
- Added `Ord` instances for `Temp` and `BlockId`.
- Built the GHC-backed HCC with `-O2`.

Direct HCC compile of the same patched TinyCC source:

```text
hcc --expand-dump ... tcc.c > tcc-expanded-new.c
wall: 0.23s
max RSS: 76,724 KiB
tcc-expanded-new.c: 1,241,347 bytes
output identical to baseline expansion

hcc -S -o tcc-new.M1 tcc-expanded.c
wall: 2.12s
max RSS: 210,688 KiB
tcc-new.M1: 508,341 lines, 14,903,462 bytes
output identical to baseline M1
```

Binary sizes after pass 1:

```text
hcc-ghc/bin/hcc 4,443,688 bytes
```

Delta:

```text
hcc -S wall: 5.58s -> 2.12s, 62.0% faster
hcc -S max RSS: 260,368 KiB -> 210,688 KiB, 19.1% lower
hcc binary size: 4,378,184 -> 4,443,688 bytes, 1.5% larger
generated M1 size: unchanged
```
