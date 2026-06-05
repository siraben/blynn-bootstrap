# HCC Memory + CPU Audit

Audit of where memory and time go when HCC compiles
`tcc-expanded.c` (the preprocessed TinyCC source, 737 KiB → 113 K IR
lines), focused on the faithful Blynn bootstrap (`hcc.m2.precisely.m2`,
`tinycc.m2.precisely.m2`).

The PR ships:

- An `HCC_RTS_ADAPTIVE_MAJOR_WORDS` knob in the patched Blynn RTS,
  overridable at C-compile time via `-D`.
- M2-friendly pointer hoisting in `evac()` / `lazy2()` / `lazy3()` of
  the RTSPrecisely portion of the patch.
- `hcc.m2.precisely.gccLowmem` + `tinycc.m2.precisely.gccLowmem` flake
  variants.
- `hcc.m2.precisely.m2Lowmem` + `tinycc.m2.precisely.m2Lowmem` flake
  variants.
- A `CompileM` representation that uses a single-constructor `Step a`
  ADT instead of `Either CompileError (a, CompileState)`.
- Two small idiomatic Haskell cleanups
  (`TextUtil.isSpaceChar`/`isDigitChar`, `SymbolTable.hash`).
- `scripts/hcc-memory-bench.sh`: reusable TSV harness.

All emitted IR is byte-identical to master per compile path.

## Workload

Single canonical input: `tcc-expanded.c`, 737,078 bytes, 113,063 IR
lines emitted. Available from `tinycc.m1.host.ghc.native` at
`share/tinycc-hcc-m1/tcc-expanded.c`. Each variant verified by SHA
prefix of the produced `.hccir`.

Harness: `scripts/hcc-memory-bench.sh`. Emits `elapsed maxrss peakres
alloc gcs prod irhash` per run from `+RTS -s` (for GHC binaries) and
GNU `time -v`.

## Headline measurements

`hcc.m2.precisely.m2` on `tcc-expanded.c`, 5-rep interleaved median.
All rows produce IR with the same sha256 prefix.

| variant | elapsed | max RSS | Δ time | Δ RSS |
| --- | ---: | ---: | ---: | ---: |
| `hcc.m2.precisely.m2` master | 120.23 s | 1721 MiB | – | – |
| `hcc.m2.precisely.m2` PR | **102.70 s** | 1737 MiB | **−14.6 %** | +0.9 % |
| `hcc.m2.precisely.m2Lowmem` PR | **115.08 s** | **1075 MiB** | **−4.3 %** | **−37.6 %** |

The default-trigger PR is the time win at essentially same RSS; the
`m2Lowmem` variant achieves *strict* "both lower" — less elapsed AND
less RSS than master.

5-rep range for noise context: master 105.94 – 144.60 s; PR default
95.17 – 137.70 s; PR Lowmem 111.15 – 140.81 s.

Companion measurements:

- `hcc.m2.precisely.gcc` (same emitted C, GCC-compiled): essentially
  unchanged; GCC's CSE already eliminated the per-cell address
  arithmetic, so the RTS hoist is neutral on this path.
- `hcc.host.ghc.native` (GHC dev escape hatch): median 3.05 s → 2.85 s
  (−7 %), max RSS unchanged.

## Where the memory and time go (audit findings)

### Blynn-VM-side (the production target)

The patched Blynn RTS already carried optional `HCC_RTS_STATS`
instrumentation that wasn't being used. With `cc -DHCC_RTS_STATS`
against `cbits/hcc_runtime.c`, the Blynn-emitted `hcc1-blynn.c`
reports `peak_hp`, `peak_live`, `peak_stack`, GC counts on stderr at
exit. Recipe:

```sh
HCC_BLYNN_C=$(nix build --print-out-paths .#hcc.blynn.c.m2.precisely)/share/hcc-blynn-c-m2-precisely
sed -E 's/enum\{TOP=16777216\};/enum{TOP=134217728};/' \
  "$HCC_BLYNN_C/hcc1-blynn.c" > /tmp/hcc1.c
nix develop .#bench -c cc -O2 -DHCC_RTS_STATS \
  /tmp/hcc1.c hcc/cbits/hcc_runtime.c -o /tmp/hcc1-stats
/tmp/hcc1-stats --m1-ir -o /tmp/out.hccir tcc-expanded.c
# stderr: "precisely RTS stats: gc=N peak_hp=N peak_live=N ..."
```

With production `TOP = 134,217,728` and the default trigger:

```text
gc=25 peak_hp=109,113,202 peak_live=25,227,122 peak_stack=8,072
```

The working set (`peak_live ≈ 25.2 M words = 192 MiB`) is dwarfed by
`peak_hp ≈ 109 M words = 873 MiB`. **Most of the 860 MiB RSS we see
under GCC compilation is just-about-to-be-collected garbage, not live
data.** The slack is governed by `HCC_RTS_ADAPTIVE_MAJOR_WORDS`,
previously hard-coded at 83,886,080 words.

Sweep of `HCC_RTS_ADAPTIVE_MAJOR_WORDS` against the GCC-compiled
binary, same `TOP=134M`, all byte-identical IR:

| adaptive_major | elapsed | max RSS | GC count | peak_hp (MB) |
| ---: | ---: | ---: | ---: | ---: |
| 83,886,080 (default) | 16.5 s | 861 MiB | 25 | 873 |
| 33,554,432 | 22.8 s | **464 MiB (−46 %)** | 64 | 472 |
| 16,777,216 | 33.2 s | **333 MiB (−61 %)** | 129 | 337 |
| 8,388,608 | 49.0 s | **267 MiB (−69 %)** | 259 | 271 |

This is the GCC-compiled binary; the curve looks different on the
M2-Mesoplanet-compiled binary because of how M2 manages heap pages
(see m2Lowmem below).

### M2-Mesoplanet codegen cost (the time gap)

The `m2.precisely.gcc` binary (22 s) and `m2.precisely.m2` binary
(124 s on old master, 120 s on current master) compile the SAME
`hcc1-blynn.c` differently — the gap is purely codegen.

M2-Mesoplanet is a single-pass C compiler with no register allocator
and no CSE. Common expressions like
`(u*)((char*)mem + n * sizeof(u))` — generated once and shared by
GCC — get re-materialised on every cell access in the M2 output. The
Blynn RTS hot path (`evac()`, `lazy2()`, `lazy3()`, `gc()`) does this
on most lines.

This PR hoists those calculations to a per-call pointer + single-add
advance for adjacent cells. Measured net on `hcc.m2.precisely.m2`:

- `evac` hoist alone: ~−5 % wall time on M2-built binary.
- `evac` + `lazy2`/`lazy3` hoists: ~−10 % wall time.

The output IR is byte-identical (`f244f8317ace` on m2). GCC-compiled
HCC is unchanged: GCC was already doing this in CSE.

### Why `m2Lowmem` needs both `TOP` and the GC trigger

The M2-compiled binary's max RSS is dominated by which heap pages it
*touches*, not by `peak_hp`. M2 codegen ends up dirtying close to the
whole arena regardless of allocation pressure (we suspect dead-store
non-elimination plus aggressive page touch from the GC's altmem swap
pattern), so `RSS ≈ 2 × TOP × sizeof(u)` for the M2 binary. The
gccLowmem variant only changes the GC trigger — which works on the
GCC binary but is ineffective on the M2 binary because the whole
arena is already dirty.

`m2Lowmem` therefore changes *two* things:

1. `HCC_RTS_ADAPTIVE_MAJOR_WORDS = 33,554,432` — 4× more frequent
   major collections.
2. `TOP = 67,108,864` — half the arena size (vs default 134 M).

The smaller `TOP` is the actual RSS lever; the tighter trigger keeps
`peak_hp` under the new ceiling so the binary doesn't hit
emergency-GC mode.

### GHC-side cost-centre profile (for context)

GHC-built `hcc1` on `tcc-expanded.c` allocates 2.5 GB to produce
1.4 MB of IR. Cost-centre profile (3.4 s, 2.68 GB alloc):

| function | %time | %alloc |
| --- | ---: | ---: |
| `hccWriteBufferedLine.\` (HccSystem) | 18.4 | 0.1 |
| `>>=.\ ` (ParseLite) | 5.5 | 3.3 |
| `hash.go` (SymbolTable) | 5.3 | 8.4 |
| `>>=.\ ` (CompileM) | 4.4 | 2.1 |
| `lexC.go` (Lexer) | 2.7 | 1.9 |
| `hccWriteBufferedText` (HccSystem) | 2.2 | 2.2 |
| `isSpaceChar` (TextUtil) | 1.9 | 3.3 |
| `pure` (CompileM) | 1.7 | 4.9 |

Heap profile by type, summed over the run, top contributors:

| type | MB allocated |
| --- | ---: |
| `[]` (cons cells) | 2090 |
| `THUNK_2_0` | 1552 |
| `THUNK_1_0` | 380 |
| `CompileState` | 172 |
| `LexState` | 149 |
| `SymbolTable.N` | 98 |
| `Token` / `Span` | 96 each |

At peak (94 MiB residency, mid-parse): 40 % cons cells, 36 % thunks,
the rest data types. The CompileM `Step` ADT change in this PR is
aimed at the `pure`/`>>=` lines above (saves 2 cells per successful
bind on the success path).

## Why this PR doesn't ship streaming

A pull-style streaming pipeline (parse-register-lower one TopDecl at
a time, never materialise the AST list) gave a clean −7 % `peak_live`
on the Blynn binary but cost +15-28 % wall time on the m2 paths
because pass 2 re-parses the token stream. The infrastructure
(`parsePullTopDecl`, `M1Ir.StreamCtx`, a generic `Hcc.Stream` conduit
module) was implemented and validated under
`tinycc.m2.precisely.m2`; it lives in git history as commits
`1a3e6ef0` and `3f7ce986` for a follow-up PR that finds a cheap way
to skip pass-2 re-parse (e.g. recording a per-function token-slice in
pass 1).

Other experiments rejected by measurement:

- **Strict `LexState` field updates** — +3 % alloc, +5 % peak RSS.
  Lazy chains were being elided.
- **String interning of identifiers** (`TokIdent` payloads,
  10.8× duplication potential) — persistent-`SymbolMap` insert
  path-copying outpaced the duplicate-string savings: +5 % GHC peak,
  +19 % Blynn `peak_live`.
- **Chunked-write emit** (`writeChunk` + `endLine` replacing the
  `++`-chain `String` write) — −16 MB intermediate cons cells but
  +800 K FFI calls and +5 % GHC max RSS. Net wash.

## Reproducing the measurements

```sh
# Build all variants
nix build --no-link --print-out-paths \
  .#hcc.host.ghc.native \
  .#hcc.m2.precisely.m2 .#hcc.m2.precisely.m2Lowmem \
  .#hcc.m2.precisely.gcc .#hcc.m2.precisely.gccLowmem

# Bench
TCC=$(nix build --print-out-paths .#tinycc.m1.host.ghc.native)/share/tinycc-hcc-m1/tcc-expanded.c
export GNUTIME=$(nix shell nixpkgs#time -c sh -c 'command -v time')
scripts/hcc-memory-bench.sh header
for bin in $(nix build --print-out-paths .#hcc.m2.precisely.m2)/bin/hcc1; do
  scripts/hcc-memory-bench.sh $bin $TCC m2.m2
done
```

For Blynn-side `peak_live` numbers, use the manual
`-DHCC_RTS_STATS` recipe in the "Blynn-VM-side" section above.
