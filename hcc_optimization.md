# HCC Optimization Log

Working metrics for improving HCC efficiency and modularity. The primary benchmark is the end-to-end TinyCC bootstrap path, with direct HCC-on-expanded-TCC measurements used to isolate compiler runtime and memory.

## Pass 12: Faithful GHC O0 profile mode

Goal: make the GHC development/profile path a closer proxy for Precisely-built
HCC, then profile the real TinyCC compile workload under that mode.

Faithful GHC settings:

```text
GHC source flags:
  -O0
  -fno-cse
  -fno-enable-rewrite-rules
  -fno-full-laziness
  -fno-specialise
  -fno-state-hack
  -fno-strictness
  -fno-worker-wrapper
  -Wall -Werror
  -XNoImplicitPrelude
  -XForeignFunctionInterface

C/runtime flags:
  -O0
  -U_FORTIFY_SOURCE
  -Wall -Werror

Nix hardening:
  hardeningDisable = [ "fortify" ]
```

Rationale:

- Precisely does not run GHC's optimizer. Use `-O0` and explicitly disable the
  major simplifier optimizations that would otherwise make the native profile a
  poor guide for the bootstrap compiler.
- Compile the C runtime side at `-O0` as well. Otherwise `hcc_runtime.c` can hide
  costs that remain visible in the Precisely-generated C path.
- Disable fortify for this derivation. Nix's default `_FORTIFY_SOURCE` emits a
  glibc warning at `-O0`, and the faithful profile path treats warnings as
  errors.

How to profile the realistic TinyCC compile path:

```sh
nix build .#hcc.profile.host.ghc.native --no-link --print-out-paths -L
nix build .#tinycc.m1.host.ghc.native --no-link --print-out-paths -L

nix develop .#bench -c bash -lc '
  profile=/nix/store/...-hcc-profile-host-ghc-native-0-unstable-2026-05-06
  artifact=/nix/store/...-tinycc-m1-hcc-host-ghc-native-unstable-2024-07-07
  work=build/hcc-ghc-o0-faithful-profile-tcc
  rm -rf "$work"
  mkdir -p "$work"
  cd "$work"
  env time -v "$profile/bin/hcc1" \
    --m1-ir -o tcc.hccir \
    "$artifact/share/tinycc-hcc-m1/tcc-expanded.c" \
    +RTS -p -s -RTS \
    > hcc1.stdout 2> hcc1.time-rts
  mv hcc1.prof hcc1-cost.prof
  env time -v "$profile/bin/hcc-m1" tcc.hccir tcc.M1 \
    > hcc-m1.stdout 2> hcc-m1.time
'
```

Profile run on 2026-05-10:

```text
hcc1 --m1-ir tcc-expanded.c:
  elapsed:              3.74s
  RTS total elapsed:    3.668s
  RTS MUT elapsed:      2.829s
  RTS GC elapsed:       0.838s
  productivity:         77.1%
  heap allocated:       6,227,785,776 bytes
  profile allocation:   2,742,146,240 bytes
  max residency:        128,000,568 bytes
  max RSS:              386,248 KiB

hcc-m1 tcc.hccir:
  elapsed:              0.38s
  max RSS:              437,368 KiB

output:
  tcc.hccir:            124,131 lines, 3,577,850 bytes
  tcc.M1:               413,834 lines, 11,790,615 bytes
  tcc.M1 sha256:        52442d38f19333d1ce26fae1230fa206f750295bdd56a8f5537e715a54fc7ef9
  cmp against native artifact tcc.M1: byte-identical
```

Top `hcc1` cost centres:

```text
hccWriteAndFlushLines                  20.5% time, 0.6% alloc
ParseLite >>=                           5.0% time, 3.0% alloc
IntTable.lookupT                        4.5% time, 0.0% alloc
Parser.removeEnumConstant               3.5% time, 1.9% alloc
hccWriteHandleLines.writeTextBuffered   3.5% time, 3.4% alloc
lexerIsSpace                            3.3% time, 4.0% alloc
SymbolTable.hash.go                     3.2% time, 4.0% alloc
IntTable.insertT.go                     2.6% time, 3.0% alloc
CompileM >>=                            2.4% time, 1.2% alloc
readRuntimeResult.go                    2.4% time, 3.5% alloc
emitInstr                               2.2% time, 6.1% alloc
```

Interpretation:

- The output side is still the largest single cost even after chunked writes:
  `hccWriteAndFlushLines` plus `HccSystem` write helpers account for roughly a
  quarter of sampled CPU.
- Parser monad bind and enum cleanup are now prominent enough to justify a
  focused parser pass, but still below output and table costs.
- `IntTable` lookup/insert is time-visible but allocation-light. That suggests
  the tree shape is acceptable for now, and further gains likely come from
  reducing how often we hit the tables.
- `hcc-m1` is fast enough that the next optimization work should stay in `hcc1`
  rather than the C M1 writer.

## Pass 8: M2-Planet C-shape benchmarks

Goal: make the C that stage0 M2-Mesoplanet sees cheaper without changing HCC semantics.

Changes:

- Restored the normal `hcc_runtime.c` after the C89-style declaration pass regressed the host runtime shape.
- Added `scripts/bench-m2-planet.sh` for M2-Planet microbenchmarks and Precisely-generated sample programs.
- Changed `hcc_runtime_m2.c` locals toward declaration initializers where M2-Planet supports them.

M2-Planet microbenchmarks:

```text
RUNS=1 COUNTS=10 nix develop -c scripts/bench-m2-planet.sh /tmp/hcc-m2-bench-runtime-check

micro init 10 m1_bytes=6637 m1_lines=271
micro assign 10 m1_bytes=7207 m1_lines=291
micro for-init 10 m1_bytes=15037 m1_lines=601
micro for-assign 10 m1_bytes=15607 m1_lines=621
```

M2-Mesoplanet sample timings:

```text
where         elapsed=1.23s maxrss=109056 KiB c_bytes=72035 bin_bytes=254406
local-syntax  elapsed=1.24s maxrss=109824 KiB c_bytes=72078 bin_bytes=254470
reverse-input elapsed=1.26s maxrss=108288 KiB c_bytes=70782 bin_bytes=251950
```

Blynn VM raw-stage sample timings:

```text
lonely-raw elapsed=10.79s maxrss=261120 KiB
patty      elapsed=8.20s  maxrss=262144 KiB
guardedly  elapsed=9.75s  maxrss=262144 KiB
```

Runtime C before/after comparison on the generated `where.c` sample:

```text
old bin=254450 m2=849479 m1=698951
new bin=254406 m2=848225 m1=698819
```

Generated Precisely C inspection:

```text
hcc1-blynn.c from stage0/GCC Precisely: 756 lines, 515707 bytes
hcc1-blynn.c largest line:             487486 bytes
root8 payload integers:                130979
non-root generated C bytes:            28220
step dispatch:                         89 lines, 4694 bytes
run dispatch:                          89 lines, 4659 bytes
```

Observations:

- M2-Planet emits smaller M1 for declaration initializers than for declaration plus later assignment. The diff removes the generic assignment path's extra `_common_recursion` push/pop around local stores.
- `hcc1-blynn.c` is dominated by one huge `static u root8[]` initializer. This is a better next target than more handwritten-runtime polish.
- The generated RTS contains two near-duplicate dispatch loops, `step` and `run`. The byte savings are smaller than compacting `root8`, but this is simple enough to benchmark.
- GHC-debug Precisely and GCC/stage0 Precisely generate slightly different C sizes for the same HCC source. The stage0 and GCC Precisely outputs match each other in the inspected build.

Validation:

```text
nix build .#hcc.m2.precisely.gcc --no-link --print-out-paths -L
pass: /nix/store/fj14nnqmr45qczz4lp1qgc651k7hwlzg-hcc-m2-precisely-gcc-0-unstable-2026-05-06

sh -n scripts/bench-m2-planet.sh
git diff --check
pass
```

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

- This repo's current Blynn target should be upstream `precisely_up`, built from the pinned `blynn/compiler` fetch plus `nix/patches/upstreams/blynn-compiler-local.patch`.
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

## Pass 5: GHC O0 write/lower profile for TinyCC M1 emission

Goal: use a GHC `-O0 -prof -fprof-auto` build to isolate the write/lower/codegen cost of compiling expanded TinyCC to M1.

Profile input:

```text
build/hcc-ghc-prof-local/run/tcc-expanded.c
bytes: 537,812
```

Baseline `--ir-summary`:

```text
wall: 2.38s
allocated: 3,637,017,680 bytes
max residency: 126,738,448 bytes
max RSS: 354,708 KiB
```

Baseline full `-S`:

```text
wall: 5.97s
allocated: 12,134,866,168 bytes
max residency: 137,627,984 bytes
max RSS: 402,320 KiB
tcc.M1: 519,924 lines, 15,498,233 bytes
```

Initial full `-S` hot spots:

```text
hccWriteHandleLines.writeTextBuffered  34.0% time, 26.9% alloc
RegAlloc.lookupAt                       5.9% time,  2.6% alloc
hccWriteHandleLines flush check         4.0% time,  1.5% alloc
RegAlloc.replaceAt                      2.5% time,  2.2% alloc
CodegenM1.storeTemp                     2.0% time,  6.8% alloc
CodegenM1.loadLocationWithRspBias       1.5% time,  6.1% alloc
```

Experiments:

- Adding `hcc_obuf_put_buffer` moved the output hot spot into `withBuffer` and regressed wall time and allocation, so it was reverted.
- Changing allocation chunk size from 32 to 8, 4, 2, and 1 showed the best throughput at chunk size 2.
- Replacing the two-entry chunk list with a two-field constructor removed the recursive `lookupAt`/`replaceAt` list path.
- Caching stack slot assembly strings inside `Location` reduced allocation slightly but more than doubled wall time because the strings were built eagerly for every allocated temp, so it was reverted.
- Replacing hex digit string indexing with branches reduced allocation slightly but regressed profiled wall time, so it was reverted.

Kept change:

- `LocationChunk` is now `LocationChunk (Maybe Location) (Maybe Location)` with `locationChunkSize = 2`.

Final kept `-S` profile:

```text
wall: 5.68s
allocated: 11,176,069,040 bytes
max residency: 137,627,984 bytes
max RSS: 402,540 KiB
tcc.M1 sha256: 0e777006c60fa1ea49b75d62dc916792748b58bcf3c13e4e911af87f6f190f9f
```

Delta from baseline full `-S`:

```text
wall: 5.97s -> 5.68s, 4.9% faster
allocated: 12.13 GB -> 11.18 GB, 7.9% lower
max residency: unchanged within measurement noise
generated M1: byte-identical for this input
```

Remaining hot spots after the kept change:

```text
hccWriteHandleLines.writeTextBuffered  35.1% time, 28.2% alloc
hccWriteHandleLines flush check         4.5% time,  1.6% alloc
Parser bind                             2.6% time,  1.2% alloc
removeEnumConstant                      2.3% time,  0.9% alloc
IntTable lookup                         2.0% time,  0.1% alloc
storeTemp                               2.0% time,  7.1% alloc
textAppend                              1.9% time,  3.2% alloc
loadLocationWithRspBias                 1.7% time,  6.4% alloc
```

Validation:

```text
GHC -O0 -prof rebuild of hcc1: pass
pp-smoke through hcpp + hcc1 --check: pass
parse-smoke through hcpp + hcc1 --check: pass
parse-smoke hcc1 -S: pass
```

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

## Pass 10: Bootstrappable data structure upgrades

Goal: implement the first batch of efficient data structures without changing generated M1 output.

Changes:

- Added `ScopeMap`, a frame-based local environment for block/function scopes.
- Changed `CompileM.csVars` from one persistent symbol tree to `ScopeMap`, so inner block bindings live in a current frame and lookups walk outward.
- Added struct layout caches in `CompileM`:
  `csStructSizes` for aggregate sizes and `csStructMembers` for member offset/type lookups.
- Changed `RegAlloc` from one `IntMap Location` keyed by every temp to a chunked dense `LocationTable`.
  Chunks hold 32 temp locations, so lookup still uses a tree but over chunk IDs instead of every individual temp.
- Changed `SymbolTable` tree nodes to store a per-key hash. Lookups compute the query hash once and compare hashes before falling back to character-by-character `String` comparison.
- Changed function-like macro argument substitution from association-list lookup to a `SymbolMap MacroArg`.
- Made `readHandle` tail-recursive in `HccSystem`.

GHC O0 direct TinyCC fixture timing:

```text
hcpp:
output byte-identical to previous expanded TinyCC source
elapsed: 2.60s
max RSS: 246,208 KiB

hcc1:
output byte-identical to previous tcc.M1
elapsed: 3.83s
max RSS: 187,712 KiB
```

Blynn/GCC HCC generation:

```text
hcc-gcc-precisely-gcc:
hcpp-full.hs: 2,823 lines, 93,574 bytes
hcc1-full.hs: 7,322 lines, 238,664 bytes
hcpp-blynn.c: 248,842 bytes
hcc1-blynn.c: 564,014 bytes
buildPhase completed in 36s
internal HCC smoke tests pass
```

TinyCC self-host validation:

```text
nix develop .#bench -c bash -lc 'nix build .#tinycc-boot-hcc-host-ghc-native .#tinycc-boot-hcc-gcc-precisely-gcc .#tinycc-boot-hcc-gcc-precisely-tcc --no-link --print-out-paths -L'
pass

tinycc-boot-hcc-host-ghc-native:
/nix/store/wrd6448ihv01x47ybj267ncyqlbk7k8x-tinycc-boot-hcc-host-ghc-native-unstable-2024-07-07

tinycc-boot-hcc-gcc-precisely-gcc:
/nix/store/dqv71d55v00vx8zbs665lpw0979c7b1l-tinycc-boot-hcc-gcc-precisely-gcc-unstable-2024-07-07

tinycc-boot-hcc-gcc-precisely-tcc:
/nix/store/mllnljnqybkzv5651034q74gi54y2j1w-tinycc-boot-hcc-gcc-precisely-tcc-unstable-2024-07-07
```

Remaining larger migrations:

- Replace `String` tokens/AST names with explicit symbol objects rather than hash-accelerated string tree keys.
- Replace list-backed token streams with cursor/index streams.
- Replace whole-source `String` lexing with slice-oriented text buffers.
- Replace `[String]` output lines with direct output builders that can flush chunks without materializing line lists.

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

## Pass 11: Chunked output-buffer writes

Goal: reduce the cost of writing generated M1 from GHC `-O0` and
Precisely-built HCC without changing generated output.

Baseline profile, GHC `-O0` profiled `hcc1 -S tcc-expanded.c`:

```text
real time: 4.677s
profile total time: 3.13s
allocated: 4,807,307,640 bytes
M1 output: 412,408 lines, 11,752,424 bytes
top hotspot: hccWriteHandleLines.writeTextBuffered, 27.1% time, 24.8% alloc
```

Changes:

- Added `hcc_obuf_put4` and `hcc_obuf_put8` runtime primitives.
- Updated `hccWriteHandleLines` to copy output text into the runtime buffer
  eight characters per FFI call, falling back to four and then one for tails.
- Implemented the same primitives in the M2-compatible runtime.

Result after `put8`:

```text
real time: 4.076s
profile total time: 2.59s
allocated: 3,926,143,128 bytes
M1 output: 412,408 lines, 11,752,424 bytes
sha256: c8fa42557d9ea036d464bacb5368688f0cb08c7cb1b76c0426c414aa565a4bfa
top hotspot: hccWriteHandleLines.writeTextBuffered, 9.8% time, 7.9% alloc
```

Validation:

```text
nix develop -c nix build .#hcc.gcc.precisely.gcc --no-link --print-out-paths -L
pass

nix develop -c nix build .#tinycc.host.ghc.native --no-link --print-out-paths -L
pass
```

Rejected experiment:

```text
Converted more of CodegenM1's per-instruction helpers to Lines builders.
Output stayed byte-identical and allocation fell only slightly, but profiled
real time regressed to 4.442s. Reverted; this needs a broader representation
change rather than a mechanical type rewrite.
```

## Pass 8: M2-Planet C-shape benchmarks

Goal: optimize the C that is compiled by M2-Planet, using C source shapes that
M2-Planet lowers to smaller M1.

Findings from `scripts/bench-m2-planet.sh`:

```text
micro init 100:       62,618 bytes, 2,521 M1 lines
micro assign 100:     68,318 bytes, 2,721 M1 lines
micro for-init 100:  147,338 bytes, 5,821 M1 lines
micro for-assign 100:153,038 bytes, 6,021 M1 lines

VM raw-stage smoke:
  lonely-raw  10.8s, ~262 MiB RSS
  patty        8.2s, ~262 MiB RSS
  guardedly    9.8s, ~262 MiB RSS
```

Source audit:

- M2-Planet's local declaration initializer path calls `expression()` and then
  `load_address_of_variable_into_register` once.
- A later assignment goes through the general assignment path and
  `common_recursion`, adding push/pop traffic in emitted M1.

Change:

- Reverted the native C89-style split-declaration pass.
- Changed `hcc_runtime_m2.c` locals from `int x; ... x = ...;` to declaration
  initializers where M2-Planet accepts them.
- Added `scripts/bench-m2-planet.sh` for repeatable M2 microbenchmarks, Precisely
  sample builds, and VM raw-stage measurements.

Measured on the generated `where` Precisely sample:

```text
old runtime: bin=254450 bytes, M2=849479 bytes, M1=698951 bytes
new runtime: bin=254406 bytes, M2=848225 bytes, M1=698819 bytes
```

Validation:

```text
RUNS=1 COUNTS=10 nix develop -c scripts/bench-m2-planet.sh /tmp/hcc-m2-bench-runtime-check
pass

nix build .#hcc.m2.precisely.gcc --no-link --print-out-paths -L
pass
```

## Pass 7: Precisely RTS generational GC experiment

Goal: reduce peak runtime memory for Blynn-compiled HCC while preserving the TinyCC self-host path.

Changes:

- Replaced the slot-log remembered set with a card table plus compact card worklist.
- Added per-card old-to-young write tracking for the experimental generational RTS.
- Tuned the stats-only generational build from a 16M-word nursery to a 64M-word nursery for large HCC inputs.

Current result:

```text
copying stats TinyCC self-host:
  nix build .#tinycc-boot-hcc-gcc-precisely-gcc-stats-copying --no-link --print-out-paths -L
  pass, build phase 3m52s
  first heavy hcpp: gc=30 major_gc=30 peak_hp=134217710 peak_live=126936632
  final heavy hcc1: gc=12 major_gc=12 peak_hp=268435438 peak_live=25536132

generational stats, 16M nursery:
  first heavy hcpp still running after ~5m at ~68 MiB RSS; stopped

generational stats, card worklist + 64M nursery:
  first heavy hcpp completed, but only via major collections:
    gc=40 minor_gc=0 major_gc=40 peak_hp=134217708 peak_live=127456650 peak_old=127456650 peak_remembered=79275
  final hcc1 still running after ~10m at ~266 MiB RSS; stopped
```

Conclusion:

The card-table generational RTS reduces resident memory on the first heavy `hcpp`
pass, but the TinyCC workload has a live set close enough to the heap ceiling that
the current collector either performs too many minor collections or falls back to
major collections. Keep this as an experimental stats target for now; use the
copying RTS for the boss build until the generational design has a real nursery
promotion policy win.

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
