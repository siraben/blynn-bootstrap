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

## Dialect audit: Blynn target

Target dialect:

- This repo's current Blynn target should be upstream `precisely_up`, built by `nix/blynn-precisely.nix` from `vendor/blynn-compiler/upstream`.
- That is the last stage of the packaged upstream `party -> multiparty -> party1 -> party2 -> crossly_up -> crossly1 -> precisely_up` chain, not the older single-file `effectively` subset.
- `precisely_up` is materially larger than the early stages: upstream `ParserPrecisely.hs` recognizes modules, imports, `qualified`, classes/instances, `data`, `deriving`, records, `type`, `do`, `case`, `\case`, guards, and FFI syntax.

Important incompatibilities found in current HCC:

- `ParserPrecisely.hs` parses module headers as a single constructor identifier, so `module Hcc.SymbolTable` and other hierarchical `Hcc.*` names need a flattening/renaming pass before direct Blynn compilation.
- Its type grammar uses unqualified type constructors, so qualified type annotations such as `Symbols.SymbolSet` and `FingerTree.FingerTree` are the wrong shape.
- `newtype` is reserved, but the audited parser path only handles `data` declarations. Treat `newtype` as unsupported until a direct probe says otherwise.
- GHC/System imports (`System.Directory`, `System.Process`, `GHC.IO.Encoding`, etc.) are outside the Blynn prelude and will need replacement or host-side staging later. The data-structure pass does not address those.

## Pass 4: Data-structure dialect shaping

Goal: keep the handrolled data structures closer to the syntax accepted by `precisely_up`, while preserving the GHC development build.

Changes:

- Replaced `newtype SymbolMap` and `newtype SymbolSet` with `data` constructors.
- Removed qualified imports/qualified type references for `Hcc.SymbolTable` and `Hcc.FingerTree`.
- Renamed exported data-structure operations to globally distinct names (`symbolSetMember`, `fingerLookupWith`, etc.) so unqualified imports stay practical.
- Removed the unnecessary `Prelude hiding` import from `Hcc.FingerTree`.

Direct HCC compile of the same patched TinyCC source:

```text
hcc -S -o tcc-dialect-ds.M1 tcc-expanded.c
wall: 2.70s
max RSS: 207,164 KiB
tcc-dialect-ds.M1: 508,341 lines, 14,903,462 bytes
output identical to baseline M1
```

Current metrics:

```text
Haskell LOC total: 5,894
hcc-ghc/bin/hcc: 4,486,184 bytes
tinycc-boot-hcc/bin/tcc-hcc-stage1: 2,767,218 bytes
tinycc-boot-hcc/bin/tcc: 338,120 bytes
```

Validation:

```text
nix build .#blynn-precisely --no-link --print-out-paths
pass

nix build .#hcc-ghc --no-link --print-out-paths
pass

nix build .#tinycc-boot-hcc .#hcc-m1-smoke .#hcc-mescc-tests
pass
```

## Pass 5: Flatten HCC module dialect and remove simple helper imports

Goal: remove the next concrete Blynn dialect blockers without changing compiler behavior.

Changes:

- Renamed HCC module declarations from hierarchical `Hcc.X` names to plain module names (`Ast`, `Parser`, `RegAlloc`, etc.).
- Updated imports to use those plain module names, and changed the GHC build to search `-iHcc`.
- Removed the remaining HCC-local qualified import and qualified constructor references for `CompileM`.
- Replaced remaining HCC-local `newtype` declarations with `data` declarations: `Temp`, `BlockId`, `Parser`, and `CompileM`.
- Removed `Data.Char`, `Data.List`, and `Numeric` imports from the core lexer/preprocessor/constant-expression path by adding local ASCII predicates and integer literal parsing.

Current remaining dialect blockers:

- `Main` still depends on GHC/System modules for command-line arguments, file IO, process execution, and path handling.
- `ConstExpr` still imports `Data.Bits`; upstream `BasePrecisely` has the needed `Bits` class, but this needs an explicit bridge instead of a GHC `Data.Bits` import.
- `Main` still uses `Control.Monad.filterM`; this should become a local helper or be removed as part of host IO lowering.

Direct HCC compile of the same patched TinyCC source:

```text
hcc -S -o tcc-dialect-flat.M1 tcc-expanded.c
wall: 6.76s
max RSS: 204,584 KiB
tcc-dialect-flat.M1: 508,341 lines, 14,903,462 bytes
output identical to baseline M1
```

Current metrics:

```text
Haskell LOC total: 5,956
hcc-ghc/bin/hcc: 4,481,384 bytes
tinycc-boot-hcc/bin/tcc-hcc-stage1: 2,767,218 bytes
tinycc-boot-hcc/bin/tcc: 338,120 bytes
```

Validation:

```text
nix build .#hcc-ghc --no-link --print-out-paths
pass

nix build .#tinycc-boot-hcc .#hcc-m1-smoke .#hcc-mescc-tests
pass
```

## Pass 6: Local constant-expression bit operations

Goal: remove `ConstExpr`'s dependency on GHC `Data.Bits`.

Changes:

- Replaced `Data.Bits` calls in `#if` constant-expression evaluation with local Integer operations.
- Implemented `bitNotInteger`, `bitAndInteger`, `bitOrInteger`, `bitXorInteger`, and arithmetic shifts.
- Preserved signed two's-complement-style identities for negative values:
  `~x = -x - 1`, `x | y = ~(~x & ~y)`, and negative `&` reductions through nonnegative complements.

Current remaining dialect blockers:

- `Main` still depends on GHC/System modules for command-line arguments, file IO, process execution, path handling, and stderr/exit behavior.
- `Main` still imports `Control.Monad.filterM`; this is now the only non-host helper import shown by the audit.

Current metrics:

```text
Haskell LOC total: 5,997
hcc-ghc/bin/hcc: 4,466,344 bytes
tinycc-boot-hcc/bin/tcc-hcc-stage1: 2,767,218 bytes
tinycc-boot-hcc/bin/tcc: 338,120 bytes
```

Validation:

```text
nix build .#hcc-ghc --no-link --print-out-paths
pass

nix build .#tinycc-boot-hcc .#hcc-m1-smoke .#hcc-mescc-tests
pass
```
