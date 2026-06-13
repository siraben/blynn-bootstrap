# The staged ML bootstrap

Each stage is one small job with a real handoff artifact, Blynn-style.
The ladder starts with the λ rungs (ccc/docs/lambda-ladder.md): the C
seed interprets only Λ0 plus what the assembler needs, and everything
named is earned in-chain:

| stage | input dialect | job |
|---|---|---|
| core-lambda | Λ0 (unary `fun`, ints, lists/pairs as builtins; runs on the C interpreter, self-hosts) | Λ0 → binary `.mzbc`, no assembler needed |
| data-lambda | Λ1 = Λ0 + strings/bytes/arrays/multi-parameter (written in Λ0, built by core-lambda) | Λ1 → binary `.mzbc` |
| parenthetical | (runs on the C interpreter) | parenthesized MZBC assembly → `.mzbc` |
| ml0-compiler | ML0, source restricted to Λ1 (built by data-lambda) | self-hosting single-pass compiler |
| adt-compiler | ML1 = ML0 + ADTs + shallow match | fork of 02 + the ADT delta |
| pattern-compiler | ML2 = ML1 + nested patterns, lists, refs, records | fork of 03 + the pattern delta |
| uncurry-compiler | ML2 (same language, optimizing codegen) | fork of 04 + uncurried known calls |

Each promoted stage recompiles itself to a fixpoint and is a conservative
extension of its parent (byte-identical output on the parent's dialect);
`ccc/tests/run-stage-tests.sh` enforces both, and the OCaml cross-check
pins host-OCaml/VM emission equivalence. The λ rungs are additionally
double-checked by diversity anchors: stage 02 built by data-lambda must
byte-equal its own self-recompile through the text-assembly path, and
stage 04 recompiles core-lambda/data-lambda back to their lambda-path
images. Stage 05 is the exception by
design: it changes CODE GENERATION (not the language), so it cannot be
byte-compared against 04 — it is verified by its second-generation
fixpoint (gen2 = gen3) and by every fixture behaving identically, and
downstream by ccc1/ccpp reproducing the same HCCIR byte-for-byte.

## Style: why the parsing looks the way it does

The stages are **single-pass parse-and-emit** compilers with mutable
cursor state. That is a bootstrappability decision, not an accident:

- core-lambda must run on the tree-walking C interpreter and compile
  itself, and stage 02 is written in the Λ1 subset that data-lambda
  compiles — dialects with **no ADTs, no match, no refs, no
  polymorphism**. Building an AST without sum types is strictly worse
  than not building one; emitting code during the parse keeps each
  compiler small enough to audit and small enough to interpret.
- Stages 03/04 are *forks* of their parent with reviewable deltas. The
  shared text is kept aligned so `diff 02 03` and `diff 03 04` show the
  dialect growth and nothing else. Rewriting a later stage in a fancier
  style would destroy that review property.
- Mutation is confined to a few well-named idioms: one-slot **cells**
  (`cell`/`get`/`set` — ML0 has no `ref`, a one-element array stands in),
  growable byte buffers (`push_byte`), and the token cursor
  (`tk`/`tint`/`tstr` plus `at_ident`/`take_ident`/`need_ident`/
  `skip_punct` accessors).

Within those constraints the stages use the functional tools the dialect
does provide:

- the binary-operator levels are one **higher-order combinator**
  (`c_binop_level`) instantiated with operator tables, not copy-pasted
  level functions;
- stage 04 parses patterns into a small **pattern AST** (`pat`/`ppath`)
  and walks it twice (tests, then binds) — the one place lookahead makes
  single-pass emission impossible;
- scoping is save/restore over persistent values where possible, and
  recursion — not loops — drives everything.

The dialect itself stays a strict OCaml subset (see `ccc/cc/PORTING.md`,
including the evaluation-order rule), so every stage also runs under host
OCaml with `ccc/tests/prelude-ocaml.ml`, and `mltc` type-checks all of
them with full let-polymorphic inference in-chain.
