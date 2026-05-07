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

Validation:

```text
nix build .#tinycc-boot-hcc .#hcc-m1-smoke .#hcc-mescc-tests
pass

nix shell nixpkgs#time -c time -v nix build --rebuild --no-link .#tinycc-boot-hcc
wall: 9.26s
client max RSS: 43,216 KiB
```

## Pass 2: Handrolled allocation finger tree

Goal: replace the library `Map` introduced in pass 1 with a local tree representation that is easier to lower toward Blynn's bootstrap dialect later. Some LOC and binary-size increase is intentional in this pass.

Changes:

- Added `Hcc.FingerTree`, a handrolled range-measured finger tree with `snoc` insertion and range-pruned lookup.
- Replaced `Hcc.RegAlloc`'s strict `Map` with `FingerTree AllocationEntry`.
- Kept the allocation API stable for codegen.

Direct HCC compile of the same patched TinyCC source:

```text
hcc -S -o tcc-fingertree.M1 tcc-expanded.c
wall: 2.33s
max RSS: 210,640 KiB
tcc-fingertree.M1: 508,341 lines, 14,903,462 bytes
output identical to baseline M1
```

Current metrics:

```text
Haskell LOC total: 5,778
hcc-ghc/bin/hcc: 4,490,240 bytes
tinycc-boot-hcc/bin/tcc-hcc-stage1: 2,767,218 bytes
tinycc-boot-hcc/bin/tcc: 338,120 bytes
```

Validation:

```text
nix build .#tinycc-boot-hcc .#hcc-m1-smoke .#hcc-mescc-tests
pass

nix shell nixpkgs#time -c time -v nix build --rebuild --no-link .#tinycc-boot-hcc
wall: 7.84s
client max RSS: 43,576 KiB
```

## Pass 3: Handrolled symbol table

Goal: remove the remaining library containers from HCC so later lowering does not need to account for `Data.Map` or `Data.Set` internals. This intentionally favors explicit local data constructors over the smallest possible GHC-native implementation.

Changes:

- Added `Hcc.SymbolTable`, a handrolled string-keyed binary tree.
- Replaced `Data.Set` in include expansion and parser typedef tracking with `SymbolSet`.
- Replaced `Data.Map` in the preprocessor macro table with `SymbolMap`.
- Audited `vendor/hcc` for remaining container imports. No `Data.Map`, `Data.Set`, `IntMap`, `Sequence`, `Vector`, `Hash`, or `Array` imports remain.

Direct HCC compile of the same patched TinyCC source:

```text
hcc --expand-dump ... tcc.c > tcc-symbols-expanded.c
wall: 0.32s
max RSS: 75,424 KiB
tcc-symbols-expanded.c: 1,241,347 bytes
output identical to baseline expansion

hcc -S -o tcc-symbols-same.M1 tcc-expanded.c
wall: 2.68s
max RSS: 209,692 KiB
tcc-symbols-same.M1: 508,341 lines, 14,903,462 bytes
output identical to baseline M1
```

Current metrics:

```text
Haskell LOC total: 5,896
hcc-ghc/bin/hcc: 4,472,616 bytes
tinycc-boot-hcc/bin/tcc-hcc-stage1: 2,767,218 bytes
tinycc-boot-hcc/bin/tcc: 338,120 bytes
```

Validation:

```text
nix build .#hcc-ghc --no-link --print-out-paths
pass

nix build .#tinycc-boot-hcc .#hcc-m1-smoke .#hcc-mescc-tests
pass

nix shell nixpkgs#time -c time -v nix build --rebuild --no-link .#tinycc-boot-hcc
wall: 7.90s
client max RSS: 44,688 KiB
```
