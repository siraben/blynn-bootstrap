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

## Split hcc1 profile: 2026-05-07

State: split driver into `hcpp` and `hcc1`, with `hcc1` profiled from the O0 GHC profiling build.

Input:

```text
hcpp tcc-expanded.c > tcc.i
tcc.i: 537,750 bytes, 1 token-rendered line

hcc1 -S -o tcc.M1 tcc.i +RTS -p -s -RTS
tcc.M1: 519,904 lines, 15,484,417 bytes
```

RTS profile:

```text
wall: 9.78s profiled elapsed
total alloc: 8,636,979,408 bytes in cost-centre profile
RTS allocated: 18,686,569,424 bytes including profiling overhead
max residency: 116,111,080 bytes
total memory in use: 343 MiB
productivity: 74.5%
```

Top individual cost centres:

```text
withBuffer              HccSystem    23.0% time 25.3% alloc
readResultAt.\          HccSystem    15.9% time  0.9% alloc
rangeContains           FingerTree    7.5% time  9.3% alloc
lookupConstant.\        CompileM      7.1% time  0.0% alloc
lookupValue             FingerTree    3.3% time  0.0% alloc
lookupGlobalType.\      CompileM      2.3% time  0.0% alloc
firstJust               FingerTree    1.7% time  0.3% alloc
byteHex                 CodegenM1     1.4% time  3.8% alloc
lookupFunction.\        CompileM      1.4% time  0.0% alloc
bindConstant.remove     CompileM      1.4% time  0.7% alloc
Parser >>=.\            Parser        1.3% time  0.8% alloc
removeEnumConstant      Parser        1.3% time  0.6% alloc
lookupNodeWith          FingerTree    1.3% time  8.2% alloc
prefixOf                Lexer         1.2% time  2.2% alloc
hccWriteHandleLines     HccSystem     1.2% time  1.2% alloc
lexerIsSpace            Lexer         1.1% time  1.3% alloc
storeTemp.\             CodegenM1     1.0% time  4.6% alloc
loadLocationWithRspBias CodegenM1     0.8% time  4.1% alloc
fingerLookupWith        FingerTree    0.7% time  3.0% alloc
joinWords               CodegenM1     0.7% time  2.4% alloc
loadImmediateBytes      CodegenM1     0.6% time  2.4% alloc
```

Audit notes:

- `HccSystem.withBuffer` and `readResultAt` are still the largest single cost. `hcc1` reads the full input through the C result buffer and writes each output line through the same buffer path. This is bootstrap-friendly, but it allocates and copies heavily under GHC. The direct fix is to add chunked handle read/write primitives in the runtime API so `hcc1` does not round-trip every input/output string through per-character Haskell lists.
- `FingerTree` is the largest compiler-internal allocation cluster. `rangeContains`, `lookupNodeWith`, and `fingerLookupWith` together account for about 20.5% allocation and 9.5% time. This is allocation lookup during codegen. Since temps are dense integers, a bootstrap-lowerable mutable or immutable dense table would fit better than a measured tree for `Allocation`.
- `CompileM` lookups are time-heavy but allocation-light. `lookupConstant`, `lookupGlobalType`, and `lookupFunction` are linear association-list scans. They are worth replacing with the same handrolled symbol table used by preprocessing/parser state before tackling smaller parser costs.
- M1 text rendering is a real allocator: `byteHex`, `storeTemp`, `loadLocationWithRspBias`, `joinWords`, and `loadImmediateBytes` are repeatedly constructing small strings. Difference-list rendering at the codegen line/chunk level should reduce allocation without changing output.
- Parser costs are present but secondary in this profile. The enum/typedef pre-scans use repeated list removals and uniqueness passes; these should be cleaned up, but only after IO, allocation lookup, and text rendering.

## Pass 8: Opaque Word output buffer

Goal: remove the worst write-side `withBuffer` cost without introducing a C pointer type that Blynn cannot represent. `precisely_up` lowers `Word` to C `unsigned`, so `Word` cannot safely hold a raw pointer on x86_64. The runtime therefore exposes `Word` as a small table handle.

Changes:

- Added runtime-managed output buffers in both `hcc_runtime.c` and `hcc_runtime_m2.c`.
- Added `hcc_obuf_new`, `hcc_obuf_put`, `hcc_obuf_write`, `hcc_obuf_clear`, `hcc_obuf_len`, and `hcc_obuf_free`.
- Changed `hccWriteHandleLines` to fill a 64 KiB output buffer and flush it to the file handle.
- Tested and discarded a GHC-only `CStringLen` writer. Per-line `CStringLen` lowered allocation but increased profiled elapsed time; chunked `CStringLen` was also slower. The portable opaque buffer remains the better result for now.

Profile on the same `tcc.i`:

```text
hcc1 -S -o tcc.M1 tcc.i +RTS -p -s -RTS
tcc.M1 byte-identical to previous output

profiled elapsed: 9.78s -> 8.71s
RTS allocated: 18,686,569,424 -> 17,994,320,120 bytes
bytes copied during GC: 4,992,060,000 -> 2,424,797,616
max residency: 116,111,080 -> 116,104,296 bytes
productivity: 74.5% -> 83.4%
```

Top individual cost centres after this pass:

```text
hccWriteHandleLines.writeTextBuffered     HccSystem 19.0% time 19.2% alloc
readResultAt.\                            HccSystem 16.1% time  0.9% alloc
lookupConstant.\                          CompileM   7.1% time  0.0% alloc
rangeContains                             FingerTree 6.9% time  9.8% alloc
lookupValue                               FingerTree 4.0% time  0.0% alloc
lookupNodeWith                            FingerTree 1.4% time  8.7% alloc
storeTemp.\                               CodegenM1  1.3% time  4.8% alloc
loadLocationWithRspBias                   CodegenM1  1.2% time  4.4% alloc
```

Validation:

```text
nix build .#hcc-host-ghc-native --no-link --print-out-paths
nix build .#hcc-profile-host-ghc-native --no-link --print-out-paths
nix build .#hcc-ghc-precisely-stdenv --no-link --print-out-paths
nix build .#tinycc-boot-hcc-host-ghc-native --no-link --print-out-paths
```

## Pass 9: Red-black symbol table and CompileM maps

Goal: make the handrolled map structure appropriate for exact string-key lookup. Finger trees are not appropriate for these maps; the hot operations are lookup/insert/delete by symbol, not sequence append/split or measured range queries.

Changes:

- Replaced the plain `SymbolTable` binary search tree with an Okasaki-style red-black tree.
- Kept delete bootstrappable by inserting tombstones rather than implementing full red-black deletion.
- Changed `CompileM` state from association lists to `SymbolMap`/`SymbolSet` for vars, structs, globals, constants, functions, and labels.

Profile on the same `tcc.i`:

```text
hcc1 -S -o tcc.M1 tcc.i +RTS -p -s -RTS
tcc.M1 byte-identical to previous output

profiled elapsed: 8.71s -> 9.67s
RTS allocated: 17,994,320,120 -> 15,852,732,416 bytes
bytes copied during GC: 2,424,797,616 -> 2,176,160,048
max residency: ~116 MB unchanged
```

Top lookup result:

```text
lookupConstant, lookupGlobalType, and lookupFunction are no longer top cost centres.
SymbolTable.compareString is the only symbol-table cost in the top set at 1.2% time and 0.0% allocation.
FingerTree remains hot: rangeContains 7.9% time / 9.9% alloc, lookupNodeWith 1.6% time / 8.8% alloc.
```

Validation:

```text
nix build .#hcc-host-ghc-native --no-link --print-out-paths
nix build .#hcc-ghc-precisely-stdenv --no-link --print-out-paths
nix build .#tinycc-boot-hcc-host-ghc-native --no-link --print-out-paths
nix build .#hcc-profile-host-ghc-native --no-link --print-out-paths
```

## Pass 10: Int-key allocation table

Goal: replace `RegAlloc`'s measured finger tree with a structure that matches the actual key shape. Allocation lookups are exact lookups by dense `Temp` integer id, not range queries or sequence splits.

Changes:

- Added `Hcc.IntTable`, a handrolled red-black `IntMap`.
- Changed `RegAlloc.Allocation` to store `IntMap Location` keyed by `Temp`.
- Removed the unused `FingerTree` module from the HCC source set.

Profile on the same `tcc.i`:

```text
hcc1 -S -o tcc.M1 tcc.i +RTS -p -s -RTS
tcc.M1 byte-identical to previous output

profiled elapsed: 9.67s -> 6.73s
RTS allocated: 15,852,732,416 -> 12,151,114,520 bytes
bytes copied during GC: 2,176,160,048 -> 2,108,657,384
max residency: ~116 MB unchanged
```

Top result:

```text
FingerTree cost centres are gone.
IntTable.intTreeLookup is 1.6% time / 0.0% allocation.
The dominant remaining costs are HccSystem write/read bridging and CodegenM1 string rendering.
```

Validation:

```text
nix build .#hcc-host-ghc-native --no-link --print-out-paths
nix build .#hcc-ghc-precisely-stdenv --no-link --print-out-paths
nix build .#tinycc-boot-hcc-host-ghc-native --no-link --print-out-paths
nix build .#hcc-profile-host-ghc-native --no-link --print-out-paths
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

## Pass 9: TCC backend validation and GHC O0 profiling

Goal: keep the fast TinyCC path green while using GHC O0 profiling to find allocation churn that should also matter to Blynn-built HCC.

Naming and bootstrap matrix changes:

- Standardized the non-stage0 C backend name as `gcc` instead of `stdenv`.
- Added `hcc-gcc-precisely-tcc` and `tinycc-boot-hcc-gcc-precisely-tcc`.
- Split generated Blynn RTS heap sizing by binary:
  `hcppTop = 134217728`, `hcc1Top = 536870912` for the GCC and TCC C backends.
- Kept the M2 backend default at one shared `top` for now while the long boss build runs.
- Added `devShells.bench` for lightweight `nix develop .#bench -c ...` profiling and status commands.

Runtime portability fix:

- Removed `strtok_r` from the host C runtime PATH scanner.
- Added fallback `WIFEXITED` and `WEXITSTATUS` macros for the TCC C backend.

Heap observations:

```text
hcppTop = 67108864:
small smoke passed
real TinyCC preprocessing corrupted later codegen with "Target label FUNCTION_main is not valid"

hcppTop = 134217728:
real TinyCC bootstrap validated
TCC-built hcpp RSS on tcc.c dropped to about 1.06 GiB
TCC-built hcc1 still uses the 512 MiB Blynn TOP and about 4.2 GiB RSS
```

GHC O0 profiling, preprocessing TinyCC:

```text
hcpp elapsed: 2.79s
hcpp max RSS: 453,696 KiB
hcpp heap allocated: 3,583,902,440 bytes
hcpp max residency: 172,945,888 bytes

top time/alloc sites:
readResultChars: 44.7% time, 9.1% alloc
lexerIsSpace: 6.7% time, 8.1% alloc
compareString: 3.9% time
isAsciiAlpha: 3.7% time, 5.2% alloc
include expansion/source builder sites: about 3.6% to 2.6% each
```

GHC O0 profiling, compiling preprocessed TinyCC to M1:

```text
hcc1 elapsed: 5.65s
hcc1 max RSS: 383,680 KiB
hcc1 heap allocated (+RTS -s): 11,261,882,952 bytes
hcc1 profiled allocation total: 5,604,210,808 bytes
hcc1 max residency: 128,864,336 bytes

top time/alloc sites:
hccWriteHandleLines.writeTextBuffered: 33.9% time, 28.1% alloc
hccWriteHandleLines.writeLinesBuffered.\: 3.9% time, 1.6% alloc
Parser bind: 2.9% time
lexerIsSpace: 2.5% time
removeEnumConstant: 2.3% time
CompileM bind: 2.1% time
storeTemp.\: 2.0% time, 7.1% alloc
loadLocationWithRspBias: 1.8% time, 6.3% alloc
textAppend: 1.5% time, 3.2% alloc
byteHexText: 1.0% time, 2.8% alloc
```

Implemented HCC changes:

- Changed M1 instruction emission to compose `Lines` difference lists instead of repeatedly appending instruction lists.
- Changed `byteHexText` to construct its four-character builder directly instead of chaining `textAppend`.

Measured effect on `hcc1`:

```text
before Lines/byteHexText changes:
elapsed: about 6.20s
heap allocated (+RTS -s): about 11.998 GiB
profiled allocation total: about 6.053 GiB

after Lines and direct byteHexText:
elapsed: 5.65s
heap allocated (+RTS -s): 11.262 GiB
profiled allocation total: 5.604 GiB
output byte-identical to the baseline tcc.M1
```

Reverted experiments:

- `hcc_result_at` to read C results forwards was byte-identical but slower:
  hcpp regressed from about 3.10s to 5.12s.
- Direct per-line C write primitive was byte-identical but slower:
  hcc1 regressed to about 7.33s.

Current validation:

```text
nix develop .#bench -c bash -lc 'nix build .#hcc-host-ghc-native --no-link --print-out-paths -L'
pass

nix develop .#bench -c bash -lc 'nix build .#tinycc-boot-hcc-host-ghc-native .#tinycc-boot-hcc-gcc-precisely-gcc .#tinycc-boot-hcc-gcc-precisely-tcc --no-link --print-out-paths -L'
pass

tinycc-boot-hcc-host-ghc-native:
/nix/store/1cj5vrfjbh12myw5pw5954lwa8cn6wwh-tinycc-boot-hcc-host-ghc-native-unstable-2024-07-07

tinycc-boot-hcc-gcc-precisely-gcc:
/nix/store/s88c3v7rdrc8wdgybv361s8dqqw6l1pf-tinycc-boot-hcc-gcc-precisely-gcc-unstable-2024-07-07

tinycc-boot-hcc-gcc-precisely-tcc:
/nix/store/z7i5y7719rv0r314m6xw3l985f0qvbqa-tinycc-boot-hcc-gcc-precisely-tcc-unstable-2024-07-07
```

Remaining optimization targets:

- `hcc1` output still spends about a third of time and allocation in per-character output buffering.
- `hcpp` still spends most of its time turning runtime output back into Haskell `String`.
- Token and identifier representation still creates many short `String` values.
- Parser and compiler monad binds are visible in O0 profiles and should be kept simple for Blynn lowering.
- Temp location loads still allocate through repeated small builder fragments.

## Pass 7: Bootstrap-size trimming

Goal: reduce the HCC program that Blynn must compile for the stage0 self-hosting path.

Changes:

- Removed derived `Show` instances from HCC datatypes and replaced the few internal diagnostics that depended on them with explicit tag/temp renderers.
- Removed development dump modes from the shipped HCC CLI: `--lex-dump`, `--pp-dump`, `--parse-dump`, `--ir-dump`, `--lower-check`, and `--codegen-check`.
- Removed temporary `cc` passthrough. The bootstrap-facing interface is now `-S`, `--expand-dump`, and `--check`.
- Deleted unused AST/IR/token renderers and unused process/env/file-output helpers from the HCC runtime shim.

Generated Blynn C metrics:

```text
before pass 7:
PROGSZ: 89064
hcc-blynn.c: 831,171 bytes
hcc-full.hs: 274,082 bytes after Show removal only
hcc-blynn-debug/bin/hcc: 910,304 bytes

after Show removal:
PROGSZ: 82048
hcc-blynn.c: 764,129 bytes
hcc-blynn-debug/bin/hcc: 837,520 bytes

after dump/passthrough trimming:
PROGSZ: 77444
hcc-blynn.c: 718,933 bytes
hcc-full.hs: 257,113 bytes
hcc-blynn-debug/bin/hcc: 788,624 bytes
```

Current metrics:

```text
Haskell LOC total: 6,972
hcc-ghc/bin/hcc: 4,133,416 bytes
```

Validation:

```text
nix build .#hcc-ghc --no-link --print-out-paths
pass

nix build .#hcc-blynn-debug --no-link --print-out-paths
pass
```

## Pass 9: O0 GHC parity build and output profiling

Goal: keep the GHC development build closer to Blynn-generated HCC and use GHC profiling to choose runtime optimizations.

Changes:

- Changed `hcc-ghc` from `-O2` to `-O0`.
- Added `hcc-ghc-profile`, built with `-O0 -prof -fprof-auto -rtsopts`.
- Added `hcc_handle_write_buffer` to both C runtimes and changed HCC line output to fill the existing runtime buffer and write each line in one C call.

Profile workload:

```text
generated C file:
800 functions
800 calls from main
function bodies use object/function-like macro expansion, arithmetic, shifts, and if/else
```

Before buffered writes:

```text
profiled elapsed: 15.70s
profiled total time: 14.73s
total alloc: 6,802,293,408 bytes
top cost centre: hccWriteHandleText, 82.0% time, 25.4% alloc
```

After buffered writes:

```text
profiled elapsed: 5.70s
profiled total time: 4.64s
total alloc: 7,680,003,240 bytes
top cost centre: withBuffer, 44.4% time, 33.8% alloc
```

Generated Blynn C metrics:

```text
PROGSZ: 69280 unchanged
hcc-blynn.c: 635,882 -> 635,963 bytes
hcc-blynn-debug/bin/hcc: 697,776 -> 697,816 bytes
hcc-ghc/bin/hcc with -O0: 3,764,728 bytes
```

Equivalence:

```text
O0 GHC hcc output matches precisely-compiled hcc output byte-for-byte for:
--expand-dump vendor/hcc/test/pp-smoke.c
-S vendor/hcc/test/parse-smoke.c
-S all vendor/hcc/test/m1-smoke/examples/*.c
```

Validation:

```text
nix build .#hcc-ghc .#hcc-ghc-profile .#hcc-blynn-debug --no-link --print-out-paths
pass

nix flake check --no-build
pass
```

Stage0 attempt:

```text
nix shell nixpkgs#time -c time -v nix build .#hcc-blynn-stage0 --no-link --print-out-paths
stopped after 3m45s in precisely_up; did not reach M2-Mesoplanet
```

## Pass 10: GHC CPU and Heap Profiling on TinyCC

Goal: profile the GHC-built HCC on the real TinyCC workload before changing data structures or splitting phases further.

Build/profile target:

```text
hcc-ghc-profile built with -O0 -prof -fprof-auto -rtsopts
runtime flags: +RTS -p -s -hc -i0.05 -RTS
workdir: build/hcc-ghc-profile-tcc
```

Artifacts:

```text
build/hcc-ghc-profile-tcc/expand.prof
build/hcc-ghc-profile-tcc/expand.rts
build/hcc-ghc-profile-tcc/expand.hp
build/hcc-ghc-profile-tcc/expand.ps
build/hcc-ghc-profile-tcc/compile.prof
build/hcc-ghc-profile-tcc/compile.rts
build/hcc-ghc-profile-tcc/compile.hp
build/hcc-ghc-profile-tcc/compile.ps
```

Outputs:

```text
tcc-expanded.c: 1,241,487 bytes
tcc.M1:        15,497,719 bytes, 519,904 lines
```

Preprocess/include expansion profile:

```text
wall: 12.93s
user: 8.33s
sys:  0.18s
total CPU profile time: 5.83s
total alloc: 786,320,096 bytes
RTS allocated: 1,648,476,512 bytes
max residency: 52,480,552 bytes
total memory in use: 111 MiB
```

Top CPU cost centres:

```text
readHandle..                         94.6% time, 19.3% alloc
readSourceWithIncludes.expandLine.keep 1.3% time, 9.4% alloc
readSourceWithIncludes.expandFile..   1.0% time, 22.1% alloc
```

Top heap-profile maxima by cost centre:

```text
readSourceWithIncludes... 28,207,648 bytes
readHandle...              6,069,888 bytes
SYSTEM                     5,338,720 bytes
readHandle...              3,405,344 bytes
readSourceWithIncludes...  1,200,000 bytes
```

Compile-to-M1 profile:

```text
wall: 44.66s
user: 43.97s
sys:  0.53s
total CPU profile time: 13.54s
total alloc: 9,792,403,736 bytes
RTS allocated: 21,095,203,632 bytes
max residency: 186,132,136 bytes
total memory in use: 379 MiB
```

Top CPU cost centres:

```text
readHandle..              39.3% time, 1.4% alloc
withBuffer                15.1% time, 22.3% alloc
lookupConstant.            4.8% time, 0.0% alloc
rangeContains              4.5% time, 8.2% alloc
lookupValue                2.3% time, 0.0% alloc
lookupGlobalType.          1.4% time, 0.0% alloc
byteHex                    1.0% time, 3.3% alloc
lookupFunction.            1.0% time, 0.0% alloc
lexerIsSpace               0.9% time, 1.5% alloc
prefixOf                   0.8% time, 2.4% alloc
```

Top heap-profile maxima by cost centre:

```text
SYSTEM                    30,885,280 bytes
readSourceWithIncludes... 27,468,096 bytes
stripComments.normal...   22,638,864 bytes
readHandle...             21,497,208 bytes
readHandle...             19,805,136 bytes
advance/takeWhileState... 14,943,936 bytes
takeWhileState.go...      12,721,632 bytes
advance/lexC.go...        11,799,296 bytes
lexIdent...               11,000,096 bytes
lexPunct.firstMatch...    10,490,144 bytes
```

Initial read:

- `ParseLite` and `ConstExpr` do not appear in the top CPU table for the full TinyCC compile; the new parser core is not the current bottleneck.
- The largest CPU costs are still host/runtime IO (`readHandle`, `withBuffer`) and allocation lookup (`FingerTree` range checks plus `CompileM` lookup wrappers).
- Heap pressure during compile is dominated by whole-source input/lexing/comment stripping and tokenization, before lowering-specific structures become visible.

## Pass 8: Remove derived equality

Goal: avoid generating equality dictionaries for internal compiler datatypes that are normally only pattern-matched.

Changes:

- Removed all remaining `deriving (Eq)` / `deriving (Eq, Ord)` clauses from HCC.
- Replaced the three actual equality requirements with local comparisons:
  temp-key comparison in `RegAlloc`, token-kind comparison in macro expansion, and an explicit associativity predicate in the parser.

Generated Blynn C metrics:

```text
before pass 8:
PROGSZ: 77444
hcc-blynn.c: 718,933 bytes
hcc-full.hs: 257,113 bytes
hcc-blynn-debug/bin/hcc: 788,624 bytes
hcc-ghc/bin/hcc: 4,133,416 bytes

after pass 8:
PROGSZ: 69280
hcc-blynn.c: 635,882 bytes
hcc-full.hs: 257,182 bytes
hcc-blynn-debug/bin/hcc: 697,776 bytes
hcc-ghc/bin/hcc: 4,025,520 bytes
```

Validation:

```text
nix build .#hcc-ghc --no-link --print-out-paths
pass

nix build .#hcc-blynn-debug --no-link --print-out-paths
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
