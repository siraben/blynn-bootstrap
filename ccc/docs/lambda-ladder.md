# The λ ladder: shrinking the C trust root

Goal: make the first programming language in the chain a recognizable
core λ-calculus (Blynn's `parenthetically → exponentially → …`
discipline), and shrink the C interpreter seed to interpret only that
core, so the named-language machinery (data structures, multi-argument
functions, the assembler) is *earned inside the chain* instead of
granted by the seed.

**Status: landed.** The cutover is complete: the seed (1326 lines, down
from 1500) interprets only the union of what `core-lambda.ml` and
`parenthetical.ml` use — gone are tuples/`fst`/`snd`, char and hex
literals, `\xNN` escapes, `and`-bindings, unary minus, `;;`,
`lor`/`lxor`/`lsl`/`lsr` and `bytes_of_string`; kept (for the assembler
and the Λ1 fixtures) are multi-parameter bindings, arrays, string
values, `not`, `land` and `asr`. The canonical chain is the ladder
below; ML0 sources no longer run on the interpreter anywhere
(`scripts/ccc-chain.sh`, the nix builds and every test suite go through
core-lambda → data-lambda → ml0).

## Dialects

**Λ0 (core lambda)** — what the shrunken seed interprets and what
`core-lambda.ml` compiles and is written in. A strict subset of ML0 and
of OCaml:

- top level: a sequence of `let name = expr` / `let rec name x = expr`
  bindings and a final `let () = expr`
- expressions: integer literals, variables, unary application `f a`
  (left-assoc), `fun x -> e`, `let x = e in e` / `let rec f x = e in e`
  (single self-recursive), `if c then e else e`, `(e)`, `e; e`
- operators: `+ - * / mod`, `= <> < <= > >=`, `&& ||` (short-circuit)
- byte buffers: `bytes_create n`, `bytes_get b i`, `bytes_set b i v`,
  `bytes_length b` — the ONE data structure. A self-hosting compiler
  cannot exist as a typed OCaml subset on closures alone (closure
  encodings of sum types need polymorphism Λ0 does not have), and a
  compiler needs identifiers and backpatchable output; bytes are both.
- builtins (fully applied): `arg_count`, `arg_get`, `open_in`,
  `open_out`, `read_byte`, `write_byte`, `close_chan`, `exit`, and
  `err_str "literal"` (string literals appear ONLY there)
- nothing else: no strings-as-values/arrays/tuples/records/ADTs/match/
  refs, no multi-parameter `let f x y`, no partial application of
  builtins

Functions are unary; multi-argument functions are written as nested
`fun`. Compound data beyond bytes is closures: environments are
FUNCTIONS from name to slot (`fun q -> if bytes_eq q n then v else
old q`), capture lists are functions from index to name. Control-flow
backpatch positions are plain ints held in recursion locals — the
recursion is the stack. This is the textbook rung.

**Λ1 (data lambda)** — Λ0 plus the machinery a real compiler wants:
string literals as values, `bytes_*`, `array_*`, `string_*` builtins,
multi-parameter `let f x y = …` with curried semantics, and `'c'`-free
character handling as in the rest of the chain. Still no tuples, ADTs,
match, refs or records. ML0's *source* (the existing
`ml0-compiler.ml`) must be Λ1 after removing its two tuple-lets.

## The new ladder

```
mlc-interp-seed.c    C seed: interprets Λ0 + the assembler's needs
                     (1326 lines, from 1500)
  → core-lambda.ml   Λ0→MZBC compiler, WRITTEN in Λ0; emits binary .mzbc
                     directly (no assembler exists yet); self-compiles to
                     a fixpoint on the seed
  → data-lambda.ml   Λ1 compiler, written in Λ0 (fork of core-lambda +
                     the data delta), compiled by core-lambda
  → ml0-compiler.ml  existing stage, source restricted to Λ1, compiled
                     by data-lambda (no longer run on the interpreter)
  → parenthetical.ml the assembler moves here: compiled by ml0; later
                     stages keep emitting text .mzs as today
  → adt-compiler.ml … pattern-compiler.ml … uncurry-compiler.ml … (unchanged)
```

## Verification

- `core-lambda` self-compilation fixpoint on the seed interpreter
- DIVERSITY ANCHOR: `ml0-compiler` (descended from the same seed via the
  other path during transition, and via Λ1 after cutover) also compiles
  `core-lambda.ml`; the two `.mzbc` must be byte-identical. This replaces
  stage 02's interp-vs-VM anchor as the cross-implementation check.
- `data-lambda` fixpoint at second generation (compiled by core-lambda,
  then by itself once it can — it is written in Λ0 ⊂ Λ1)
- every existing downstream gate (conservative extensions, mltc, ccc1/
  ccpp parity, DDC at M1, tcc self-host fixpoint) is unchanged
- host OCaml: Λ0 and Λ1 are OCaml subsets, so both new stages also run
  under `ocaml` with the existing prelude (crosscheck gate extended)

## Transition plan (historical)

The new rungs landed additively (each gated) while the then-current
interp-runs-ML0 chain kept working; the seed shrink and chain rewire
were the last, single cutover commit. The measured outcome: the seed
keeps the assembler's data machinery (multi-parameter bindings, arrays,
strings), so it interprets Λ1-shaped programs rather than bare Λ0 —
rewriting `parenthetical.ml` onto bytes alone would have cost far more
source than the ~170 C lines it could save.
