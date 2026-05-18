# Plan — CCC Bootstrap Path

This plan replaces the existing Blynn/HCC path with **CCC** (the **Caml C
Compiler**), a C compiler written in a MinCaml-style mini-OCaml subset and
hosted on a small ZINC-based bytecode VM. The motivating reference is Sumii's
*MinCaml: A Simple and Efficient Compiler for a Minimal Functional Language*
(FDPE 2005) — a ~2000-line ML compiler whose pipeline (parse → typecheck →
K-normalize → α/β/let-flatten/inline/constant-fold/elim → closure conversion
→ virtual asm → register alloc → emit) is the architectural template we follow.

The aim is the same as today: an auditable path from the stage0 seed to TCC,
then through the usual GCC chain. What changes is the implementation language
of the C compiler (precisely Haskell → mini-OCaml) and its runtime (Blynn's ION
combinator graph reducer → a small ZINC-style bytecode VM).

---

## 1. Why pivot

The current chain — `hex0 → stage0 → M2-Planet → precisely_up (Blynn) → HCC →
TinyCC → GCC` — works, but carries two pieces of "machinery debt":

- **`precisely_up`** is a deep tower of Blynn party stages
  (`methodically → crossly → precisely → precisely_up`) implementing a lazy
  Haskell-ish language by combinator graph reduction. Auditing it requires
  understanding Blynn's combinatorial calculus, ION encoding, and the chain of
  self-applied source rewrites. The audit surface is large and unusual.
- **HCC** is ~7k LoC of Haskell that targets `precisely_up` semantics. The
  Haskell-ish surface forces extra plumbing (lazy thunks, `IORef`-style
  state, ad-hoc monad encoding) that does not pay off for a strict imperative
  compiler.

MinCaml's argument is that a strict, monomorphic, higher-order ML is small,
direct, and pleasant for compiler work. Pairing it with the ZINC abstract
machine — the same machine OCaml's bytecode interpreter is built on, and one
of the most studied small functional VMs — gives us a runtime whose semantics
are documented in standard references and whose interpreter loop fits in
roughly a thousand lines of conservative C.

Net effect: a bootstrap whose "exotic" hop (M2-Planet C → functional VM) is a
single ~1k-LoC C file, and whose compiler logic lives in a strict
straightforwardly-readable language.

---

## 2. Target bootstrap chain

```text
hex0 seed
  → stage0-posix tools
  → M2-Planet
  → mzvm-seed         (ZINC VM, ~1k LoC of M2-compatible C)
  → mlc-interp-seed   (tree-walking core-ML interpreter, M2-compatible C)
  → mlc stage 0..N    (parenthetical/level-file style handoff stages)
  → mlc.byte          (self-hosted mini-OCaml compiler, ~1.5k LoC of mini-OCaml)
  → ccc.byte          (C → M1 asm compiler, ~5–8k LoC of mini-OCaml)
  → TinyCC
  → gcc 4.6 → later GCC stages
```

The two pieces we own end-to-end:

- **mzvm** — the ZINC-style VM. Two implementations:
  - `mzvm-seed.c` — M2-Planet compatible; the only "exotic" C in the chain.
  - `mzvm.c` — a richer build for native development (same bytecode ABI; lets
    us reuse host tools like `cc` for fast iteration).
- **mlc** — the mini-OCaml compiler. Two implementations:
  - `mlc-interp-seed.c` — M2-Planet compatible, hand-written. It is a
    tree-walking interpreter for the tiny core language used to run the first
    ML bootstrap stages.
  - `mlc-seed.c` — transitional M2-compatible direct bytecode compiler for
    current smoke coverage. It should shrink out of the critical path as the
    staged ML compiler takes over.
  - `mlc.ml` — the real, self-hosted compiler, written in its own input
    language. The shipped `mlc.byte` artifact is what the staged bootstrap
    reproduces.

**ccc** is the actual C compiler, structured as a port of HCC's pass list onto
mini-OCaml. It emits M1 assembly directly — no textual IR layer — feeding the
stage0 `M1` + `hex2` chain to native machine code. Dropping HCC's IR removes
one whole pass (`hcc-m1` and the `TypesIr` / `M1Ir` modules) and the file
boundary it implies; codegen is just the last pass of `ccc`.

---

## 3. Source language: mini-OCaml subset

Following MinCaml almost verbatim, with the small extensions a C compiler
needs:

**Kept from MinCaml**
- Strict, impure, monomorphic, higher-order.
- Forms: literals, arithmetic, `if`, `let`, `let rec ... and ...`, tuples,
  `let (x,y) = ...`, arrays via `Array.create` / `a.(i)` / `a.(i) <- v`,
  function application (uncurried — partial application is explicit).
- Hindley–Milner monomorphic type inference; free variables are external.
- Runtime GC is provided by `mzvm`; the source language has no finalizers or
  GC-visible hooks.

**Additions we need**
- **Bytes / strings.** A `bytes` type backed by a byte array with `b.[i]` /
  `b.[i] <- c` and `Bytes.create n`. Strings are immutable bytes. Needed
  pervasively in the C compiler for tokens, identifiers, M1 output.
- **Algebraic data types and pattern matching.** CCC source should use proper
  ML-style variants and `match ... with` forms. We should not write source
  programs that manually encode sums as `(tag, payload)` tuples or integer
  discriminants by convention. `mlc` owns the pattern compiler: it type-checks
  variant constructors, lowers nested/or/refutable patterns into decision
  trees, inserts field bindings, and emits the VM tests and branches as a
  backend detail. This adds compiler work, but it makes the later `ccc.ml`
  port clearer because ASTs, tokens, C types, and diagnostics can use direct
  constructors.
- **Association lists / int-keyed maps** as ordinary library data, not
  builtin. HCC already runs this way.
- **Primitives for I/O**: `read_byte`, `write_byte`, `open_in`, `open_out`,
  `exit`. Kept minimal — only what `mlc` and `ccc` actually call.

**Explicitly out**
- Polymorphism, records, modules, functors, objects, exceptions, finalizers,
  floats
  (we do not need floats for the C-compiler path; we drop MinCaml's float pipe
  entirely), SPARC backend.

Dropping floats removes a meaningful slice of MinCaml's surface (float
registers, FAddD, float constant tables) and is a real simplification we can
take because no link in the chain — `ccc`, `mlc`, the runtime — does
floating-point.

---

## 4. The ZINC VM (`mzvm`)

ZINC is Leroy's abstract machine for an ML-style language with curried
functions and shared closures (the "ZAM"). We use a strict subset of it,
sufficient for compiled mini-OCaml.

**Runtime layout**
This is an implementation ABI for generated bytecode, not the source language.
Source programs see constructors and pattern matching; only `mlc` and `mzvm`
care about tags and fields.

- Two fixed semispaces with a Cheney-style copying collector. Allocation is
  bump-pointer within the active semispace; collection copies live blocks from
  VM roots (`acc` and stack) into the reserve semispace.
- Boxed values are pointer-tagged: low bit `1` = immediate int, low bit `0`
  = block pointer. Each block has a header (tag, size).
- An evaluation stack and a return stack (Forth-style split is convenient for
  small interpreters; alternative is OCaml's unified stack).

**Bytecode**
A compact instruction set, roughly OCaml-bytecode-shaped:
- Stack: `ACC n`, `PUSH`, `POP n`, `ASSIGN n`.
- Environment: `ENVACC n`, `OFFSETCLOSURE n`.
- Closures: `CLOSURE lbl,n`, `CLOSUREREC ...`, `APPLY n`, `APPTERM n,s`,
  `RETURN n`, `GRAB n`, `RESTART`.
- Allocation: `MAKEBLOCK tag,n`, `GETFIELD n`, `SETFIELD n`.
- Control: `BRANCH`, `BRANCHIF`, `BRANCHIFNOT`, `SWITCH`.
- Primitives: `CONST n`, `ADDINT`, `SUBINT`, ..., `C_CALL n,prim`.
- I/O / syscalls via a fixed table of C primitives indexed by `prim`.

The `GRAB`/`RESTART`/`APPTERM` triple is exactly what makes ZINC fast on
curried calls — but mini-OCaml is uncurried at the call boundary, so a
first cut can omit `GRAB`/`RESTART` and treat all functions as taking a
tuple. We keep the door open for full ZAM-style curried calls later if
needed for compiler speed.

**Implementation**
- `mzvm-seed.c`: M2-Planet-compatible C. No floats, no `printf` format
  specifiers beyond what `mes`/M2 supports, no `qsort`, no `setjmp`. About
  800–1200 LoC.
- `mzvm.c`: same bytecode, optionally with computed-goto dispatch and
  better error messages; only for dev iteration.

A bytecode header records the magic, version, code length, primitive table
length, and global count. The file format must be **fully reproducible** —
no timestamps, no path-dependent strings — because we will diff `mlc.byte`
build outputs as a self-host check (see §7).

---

## 5. `mlc`: mini-OCaml → ZINC bytecode

Follow MinCaml's pass list essentially unmodified. Module / LoC estimates
are MinCaml-anchored, adjusted for the deletions above (no floats, no
register allocator on the target).

| Pass                         | MinCaml LoC | Notes                                       |
|------------------------------|------------:|---------------------------------------------|
| Lexer                        | 100         | Hand-written, no `ocamllex` (we have none). |
| Parser                       | 200         | Recursive descent, no `ocamlyacc`.          |
| Type inference (HM mono)     | 175         |                                             |
| K-normalization              | 195         |                                             |
| α-conversion                 | 50          |                                             |
| β-reduction                  | 45          |                                             |
| Let-flattening               | 25          |                                             |
| Inline expansion             | 50          |                                             |
| Constant folding             | 50          |                                             |
| Elimination of unused defs   | 40          |                                             |
| Closure conversion           | 140         |                                             |
| **Bytecode emit (ZINC)**     | ~250        | Replaces MinCaml's SPARC virtual asm + reg alloc + emit (~770 LoC). |
| Runtime stubs / driver       | 100         |                                             |

Estimated total: ~1400–1600 LoC of mini-OCaml.

Bytecode emission for ZINC needs no register allocator — the stack is the
register file — which is the largest single saving versus MinCaml's
hardware-asm pipeline.

The C root should stay much weaker than the full source language. It is not the
first real implementation of pattern matching, and it should be a tree-walking
interpreter rather than an increasingly strong one-shot compiler. Its source
language is a core ML bootstrap language oriented around variables, literals,
lambdas or direct functions, application, `if`, `let` / `let rec`, tuples,
arrays/bytes, and primitive I/O. It should not grow a full ADT declaration
parser or pattern compiler.

The first staged handoff should follow the early Blynn pattern exemplified by
`parenthetically`: a small stage fully parses a tiny next-stage language and
emits the next runnable image. In this tree, `01-parenthetical.ml` is that
first handoff: it runs under `mlc-interp-seed`, parses a parenthesized MZBC
assembly source, and emits a `.mzbc` image that `mzvm-seed` executes.
The next stage should stop being assembly-shaped: `02-ml0-compiler.ml` runs in
the same first language, parses a tiny but complete ML0 source dialect, lowers
it to VM bytecode, and emits a `.mzbc` artifact. From there we increase the
compiler dialect by stages until it can compile the current compiler source,
then the full `ccc`.
Every promoted compiler stage must eventually satisfy the handoff invariant:
it compiles its own source and the next compiler source. Smoke stages may exist
to grow the dialect, but they are not treated as self-hosting stages until that
check passes.

The first real parser/compiler for ADTs and `match` lives in `mlc.ml` itself:
`mlc.ml` parses the full mini-OCaml source language, represents constructors
and patterns as real AST nodes, lowers pattern matching to the core language,
then emits `.mzbc`. The C interpreter only needs enough core-language support
to run the named ML bootstrap stages that build the first `mlc.byte`.

To keep this sane:

- We constrain the interpreter-run bootstrap stages to the core subset above.
- Full source programs, including later `ccc.ml`, use proper constructors and
  `match`; they are accepted by `mlc.byte`, not by the C seed.
- A unit-test corpus should cover both layers: seed-core fixtures for
  `mlc-interp-seed.c` / transitional `mlc-seed.c`, and full-language fixtures
  for `mlc.byte` once it exists.

---

## 6. `ccc`: C → M1 assembly

Structurally a port of HCC, collapsed into two stages instead of three:

```
ccpp  preprocess
cc1   lex → parse → semantic → lower → emit M1
```

No textual IR. Lowering produces M1 directly into an output buffer. This
diverges from HCC, which serialises a typed IR through `hcc-m1.c` so that
backend was implementable in C. With `ccc` already in mini-OCaml, that
intermediate hop has no purpose — we delete it.

Mapping HCC → CCC:

| HCC module                | CCC plan                                     |
|---------------------------|----------------------------------------------|
| `Hcc.Lexer`               | direct port                                  |
| `Hcc.Preprocessor`        | direct port                                  |
| `Hcc.Parser` / `ParseLite`| direct port; drop laziness                   |
| `Hcc.TypesAst`            | direct mini-OCaml ADTs; proper `match` forms compiled by `mlc` |
| `Hcc.TypesIr` / `M1Ir`    | **deleted**; replaced by direct M1 emission  |
| `Hcc.SymbolTable` / `ScopeMap` | reuse algorithm, swap `Map` → assoc lists or sorted arrays |
| `Hcc.Lower*`              | direct port; this is the bulk of the LoC. Output target changes from `M1Ir` constructors to M1 text fragments. |
| `hcc-m1.c` (C backend)    | **deleted**; its logic folds into `Lower*`'s emission helpers |
| `Hcc.IncludeExpand`       | direct port                                  |
| `CompileM` (monad stack)  | becomes explicit state-threaded `(state, x)` returns |

Because M1 emission now lives inside `ccc.ml`, all per-architecture knobs
(amd64 vs i386 register naming, calling conventions) move from
`hcc_m1_arch_*.c` into mini-OCaml. The architecture split stays — it just
ends up as data tables / a small dispatch module inside `ccc`, not as
separate C files.

The single highest-risk port is the monad stack: HCC threads a compile-state
monad through most of `Lower*`. In mini-OCaml we have no monads, so this
becomes either (a) explicit `(state, x)` tuple returns, or (b) a mutable
`Array.create 1 state` reference. (a) is preferred for auditability; (b) is
the escape hatch where readability suffers.

Same design principles apply as for HCC (see [[hcc-design-principles]]):
**conservative > complete**, *reject is OK*, **TCC must bootstrap**, *no
TCC-overfit*. These priorities transfer unchanged.

---

## 7. Auditable steps

Each step below is a Nix flake target (or script) that produces a
deterministic artifact. The whole chain must be byte-reproducible from a
clean checkout. Suggested progression — order also matches the build order
of the eventual chain:

1. **`mzvm-seed.m2`**: M2-Planet compiles `mzvm-seed.c` to a native binary.
   Self-check: runs a tiny bytecode test program (hand-encoded) and prints
   `OK`.
2. **`mzvm.host`**: host-cc build of the same source family for dev. Both
   binaries must agree on the test corpus.
3. **`mlc-interp-seed.m2`**: M2-Planet compiles `mlc-interp-seed.c`.
   Self-check: interprets the first core stage and matches the host-built
   interpreter output.
4. **`mlc stage 0..N`**: the C interpreter runs named ML bootstrap stages.
   Early stages follow Blynn's parenthetical level-file style: each stage
   fully parses the next stage's small source language and emits the next
   runnable artifact. Later stages converge toward the fuller
   `methodically → party → crossly → precisely` style, where a stage consumes a
   source bundle with parser/type/runtime/compiler pieces and emits the next
   compiler.
5. **`mlc.byte`** (committed): the staged ML compiler compiles `mlc.ml` →
   `mlc.byte`.
   This artifact is checked into the tree the first time. Thereafter the
   committed `mlc.byte` is what runs in CI, while the staged bootstrap is
   exercised only to verify it.
6. **`mlc.byte.selfhost`**: `mzvm mlc.byte mlc.ml` produces bytecode that
   must byte-equal `mlc.byte`. (Fixed-point self-host check.)
7. **`ccc.byte`**: `mzvm mlc.byte ccc.ml` produces the C-compiler bytecode.
8. **`tcc.m1`**: `mzvm ccc.byte tcc.preprocessed.c` produces M1 assembly
   directly.
9. **`tcc.bin`**: stage0 `M1` + `hex2` assemble and link. Smoke-tested
   against the current TCC bootstrap fixtures.
10. **`gcc46.m2.ccc.m2`**: the new analog of `gcc46.m2.precisely.m2`.
11. **`gccLatest.m2.ccc.m2`**: end-to-end target.

The **diverse double-compilation** check rides on step 6: if the staged
bootstrap path rooted in the C interpreter and `mlc.byte` agree on the bytecode
for `mlc.ml`, then a Trojan in `mlc.byte` would have to be reproduced in the
plain hand-audited C/root-stage path.

A second DDC check rides on step 9: TCC bootstrapped via CCC must produce
the same TCC that today's HCC chain produces (modulo deterministic-build
caveats). For the transition period we run both chains and diff.

---

## 8. Migration: side-by-side, then retire

Phased so the existing chain keeps working through every commit:

**Phase A — VM and self-host language (no C compiler yet).**
- Land `mzvm-seed.c`, `mzvm.c`, `mlc-seed.c`, `mlc.ml`.
- Land flake targets 1–5. The full HCC chain still ships TCC and GCC.
- Reviewer benefit: easy to audit in isolation; no impact on TCC build.

**Phase B — Port CCC behind a feature flag.**
- Port HCC pass-by-pass to `ccc.ml`, keeping HCC alive.
- After each pass port, run `ccc` on the HCC test corpus and diff M1 output
  against HCC byte-for-byte. (HCC already preserves byte-identical M1 output
  on cleanup — same discipline applies. Because CCC skips the IR layer,
  parity is checked at the final M1 boundary, not at an IR boundary.)
- Land `tinycc.m2.ccc.m2` as a parallel target.

**Phase C — Cut over.**
- Once `gcc46.m2.ccc.m2` and `gccLatest.m2.ccc.m2` are green, demote HCC to
  a `legacy/` subtree and retire `precisely_up` from the default chain.
- Keep HCC buildable for one release cycle as an emergency fallback and a
  cross-validation alternate.

---

## 9. Open questions

- **Curried calls in mlc.** First-cut `mlc` will not implement
  `GRAB`/`RESTART`; instead, every function takes one tuple argument. This
  simplifies the bytecode but loses ZINC's main performance win. Decide
  whether compile time of `ccc.ml` is tolerable without it. If not, add
  `GRAB`/`RESTART` after the chain is stood up — purely a `mlc` codegen and
  `mzvm` change, no source-language churn.
- **Reproducibility of `mlc.byte` in tree.** Committing a binary artifact
  to a bootstrap repo has the obvious "trust" question. Mitigation: step 5
  enforces byte equality between `mlc-seed`-built and committed bytecode in
  CI on every commit; reviewers can rebuild from scratch via M2-Planet.
- **String encoding.** UTF-8 vs. raw bytes for source identifiers. HCC is
  byte-clean; we should match.
- **64-bit vs 32-bit values in `mzvm`.** ZINC traditionally word-tagged on
  the host word size. M2-Planet supports both amd64 and i386. Choose
  word-size-agnostic bytecode but allow the interpreter to be specialized
  per target — simplest is `intptr_t` everywhere.
- **Where to land error messages.** HCC favors *reject loudly*. The CCC
  port preserves this, but we should write one document of canonical
  diagnostic text so the parity diff against HCC stays meaningful.

---

## 10. Risks

- **LoC creep.** MinCaml is 2000 LoC partly because it has 4 source forms,
  no preprocessor, no real-world C surface. CCC is a C compiler, so the
  LoC will be HCC-shaped (~5–8k). The savings come from the deletion of
  `precisely_up`, not from `ccc` being smaller than HCC.
- **Hand-translation drift.** `mlc-seed.c` must track `mlc.ml`. Mitigation:
  step 5 makes drift a hard build failure; we should also keep `mlc.ml`
  intentionally boring so the translation is mechanical.
- **M2-Planet C subset.** `mzvm-seed.c` and `mlc-seed.c` together push the
  M2 subset harder than HCC does today. Build a small "what M2 accepts"
  cheat sheet from existing HCC C bits before writing new C.
- **Performance.** ZINC bytecode is ~10–30× slower than native. `ccc`
  compiling TCC under `mzvm` may be slow enough to need a host-cc dev path
  (`mzvm.host`) for iteration. That's fine — the audited path is the slow
  one.

---

## 11. Near-term work

- Spike `mzvm-seed.c` and run a hand-encoded "print 42" bytecode test
  through it under M2-Planet. This is the cheapest disproof of the plan.
- Sketch `mlc.ml` against MinCaml's actual source for an LoC sanity check
  on the no-float, no-register-alloc trim.
- Audit HCC's hot modules (`Lower*`, `Parser`, `Lexer`) for any feature that
  would not survive a port to a strict, monad-free language. Specifically:
  any reliance on lazy evaluation for tying knots in symbol tables.
- Pick a name for the bytecode file extension and lock the header layout
  before any bytecode is shipped.
