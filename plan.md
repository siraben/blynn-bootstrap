# CCC bootstrap plan

CCC (the Caml C Compiler) is a C compiler written in a small ML dialect and
bootstrapped on the M2-built `mzvm` bytecode VM. This document describes the
implementation in the repository, the checks that support its claims, and the
remaining work toward direct M1 emission.

The existing Blynn/HCC path remains available as a comparison and fallback.
CCC currently replaces the frontend only: `ccpp` and `ccc1` emit textual HCCIR,
then the existing M2-built `hcc-m1` backend emits M1. Direct M1 emission is a
future milestone, not a property of the current `ccc.asHcc` artifact.

## Current chain

```text
hex0 → stage0-posix → M2-Planet
  → mzvm + mlc-interp-seed
  → core-lambda → data-lambda → ML0 → ADT → pattern → uncurrying stages
  → mltc type-check gate
  → ccpp → ccc1 → textual HCCIR → hcc-m1 → TinyCC → GCC
```

The stages are checked in `scripts/ccc-chain.sh` and in the Nix derivations.
The portable entry point is `scripts/bootstrap-ccc.sh`; its default output is
`build/tinycc-boot-ccc/bin/tcc`.

### Components

- `ccc/vm/mzvm.c` is the M2-compatible bytecode VM. Its native and M2 builds
  share the `.mzbc` format documented in [`ccc/docs/mzbc.md`](ccc/docs/mzbc.md).
- `ccc/seed/mlc-interp-seed.c` is the tree-walking interpreter for the first
  lambda rung. It is intentionally weaker than the later ML stages.
- `ccc/stages/` contains the staged ML compilers. Each stage has one handoff
  artifact and is checked for the fixpoint or conservative-extension property
  appropriate to that stage.
- `ccc/mlc/mltc.ml` is the in-chain Hindley–Milner checker. It checks itself,
  the staged compilers, and the concatenated `ccc1` and `ccpp` sources before
  those sources are compiled.
- `ccc/cc/` is the HCC pass-list port. `ccpp` preprocesses C; `ccc1` lowers
  preprocessed C to textual HCCIR; `hcc-m1` converts HCCIR to M1.

## Why this architecture

The Blynn/HCC path works, but it has a large audit surface: `precisely_up` is a
deep combinator-reduction tower and HCC carries a Haskell-oriented runtime
model. CCC uses a small strict ML dialect and a compact bytecode VM. The
language is expressive enough for the compiler while keeping the seed tools
small and M2-Planet-buildable.

The current HCCIR boundary is deliberate. It lets CCC be compared with HCC at
the frontend boundary while the backend remains the existing, audited M2 C
program. Removing that boundary is tracked as a separate milestone.

## Source language and stages

The staged language grows in small, reviewable extensions:

| Stage | Extension | Verification |
| --- | --- | --- |
| core-lambda | Λ0 lambda calculus with integers and symbolic cons cells | seed-interpreted self-fixpoint |
| data-lambda | strings, arrays, bytes, and multi-argument bindings | lambda-path byte parity |
| ML0 | single-pass compiler for the Λ1 subset | self-compilation and stage handoff |
| ADT | algebraic data types and shallow matching | conservative extension |
| pattern | nested patterns, lists, refs, and records | conservative extension and fixtures |
| uncurrying | optimized code generation for known saturated calls | second-generation fixpoint |

The source language is strict. It has algebraic data types, records, mutable
cells, arrays, bytes, and a small I/O primitive set. The VM supplies a copying
collector. `mltc` provides let-polymorphic type inference with the value
restriction; source programs that fail the checker are rejected before code
generation.

The seed interpreter does not implement the full language. It runs only the
first lambda rung and the small set of operations needed by the early
assembler. Later features are earned by the staged compilers rather than
being part of the C trust root.

## HCC-to-CCC porting rules

The port preserves HCC's observable behavior at the current boundary.

- HCCIR output is byte-for-byte identical on the corpus and TinyCC fixture.
- Evaluation order is explicit. Effects such as fresh IDs, labels, and data
  items remain in Haskell's order.
- Haskell's flooring `div` and `mod` use the helpers in `ccc/cc/prim.ml`.
- Diagnostics, quoting, and target metadata use the same spelling as HCC.
- Haskell module names map mechanically to snake_case ML names. The manifest
  files `ccc/cc/PARTS-cc1` and `ccc/cc/PARTS-ccpp` define concatenation order.

The detailed source restrictions and naming rules are in
[`ccc/cc/PORTING.md`](ccc/cc/PORTING.md). They are implementation notes for
contributors, not a second description of the bootstrap chain.

## Verification and evidence

The required CCC derivation is `tests.ccc.golden`. It runs the packaged
`ccc.asHcc` path through phase-boundary golden tests and target checks. The
repository also provides focused scripts for the VM, lambda stages, ML stages,
host-OCaml cross-checks, M2 seed builds, type checking, lexing, parsing, IR,
and preprocessing.

The supported target checks cover amd64, aarch64, riscv64, and i386. The
portable smoke path has been validated on Alpine for amd64 and aarch64. The
portable TinyCC self-host fixpoint remains enabled only on amd64; aarch64
support is a tracked follow-up.

The current implementation has these independent parity anchors:

1. `core-lambda` self-compiles to a byte-identical image on the seed path.
2. The staged ML bootstrap reaches the required fixpoints; stage 05 uses a
   second-generation fixpoint because it changes code generation.
3. `mltc` checks the compiler sources in-chain before compilation.
4. `ccpp` output matches HCC preprocessing output.
5. `ccc1` HCCIR matches HCC on the corpus and TinyCC input.
6. The M2-built CCC frontend and the existing `hcc-m1` backend reproduce the
   reference TinyCC M1 artifact on the checked-in fixture.

These checks establish the current phase boundaries. They do not establish
that CCC already emits M1 directly or that every portable self-host target is
complete.

## Performance notes

The repository records one same-machine serial measurement in the PR
description: CCC completes the measured TinyCC endpoint in about 194 seconds,
compared with about 591 seconds for the HCC path and 1,166 seconds for the
MesCC path. These are reproducibility-oriented measurements, not a benchmark
suite; hardware, source pins, warm state, and endpoint definitions matter.

The largest measured VM costs are the M2-generated dispatch loop and the
symbolic lambda rung's linear global lookup. The uncurrying stage reduces
closure traffic for known saturated calls. The cost model and accepted M2
subset are documented in [`ccc/docs/m2-codegen.md`](ccc/docs/m2-codegen.md).

## Nix and portable interfaces

The main CCC outputs are:

- `ccc.asHcc`: the complete CCC frontend plus the HCC-compatible command-line
  wrappers and M2-built `hcc-m1` backend.
- `ccc.chain`: a host-compiler development build of the chain.
- `ccc.tinycc` and `ccc.tinyccM1`: TinyCC artifacts produced through CCC.
- `ccc.tinyccPreprocInputs`: the preprocessing input fixture used for parity.

Use `nix build .#tests.ccc.golden` for the required CCC checks. Use
`sh scripts/bootstrap-ccc.sh` for the portable path; set `M2_ARCH` and `M2_OS`
when selecting a target explicitly.

## Remaining milestones

The open work is deliberately separate from the current implementation:

1. Replace textual HCCIR plus `hcc-m1` with a direct M1 backend.
2. Promote the full fixture, host-OCaml, and M2-seed suites to required CI
   jobs where their runtime permits.
3. Enable and verify the portable TinyCC self-host fixpoint on aarch64.
4. Add a reproducible CCC-versus-Blynn/HCC benchmark job.

`TASKS.md` is the status ledger for these milestones. Update it when a check or
architectural boundary changes; keep design rationale in this document and
implementation rules in the CCC source documentation.
