# The λ ladder: shrinking the C trust root

Goal: make the first programming language in the chain a recognizable
core λ-calculus (Blynn's `parenthetically → exponentially → …`
discipline), and shrink the C interpreter seed to interpret only that
core, so the named-language machinery (data structures, multi-argument
functions, the assembler) is *earned inside the chain* instead of
granted by the seed.

**Status: landed** (and revised: Λ0 is now the *symbolic* core, v2
below). The seed interprets only the union of what `core-lambda.ml` and
`parenthetical.ml` use — gone are tuple syntax, char and hex literals,
`\xNN` escapes, `and`-bindings, unary minus, `;;`,
`lor`/`lxor`/`lsl`/`lsr` and `bytes_of_string`; kept (for the assembler
and the Λ1 fixtures) are multi-parameter bindings, arrays, string
values, bytes, `not`, `land` and `asr`; added for Λ0 v2 are the
list/pair cell builtins (`cons`/`nil`/`null`/`hd`/`tl`,
`pair`/`fst`/`snd` — 2-field blocks matching the VM, so programs behave
identically interpreted and compiled). The canonical chain is the
ladder below; ML0 sources no longer run on the interpreter anywhere
(`scripts/ccc-chain.sh`, the nix builds and every test suite go through
core-lambda → data-lambda → ml0).

## Dialects

**Λ0 (core lambda, v2)** — what the shrunken seed interprets and what
`core-lambda.ml` compiles and is written in. A strict subset of ML0 and
of OCaml:

- top level: a sequence of `let name = expr` / `let rec name x = expr`
  bindings and a final `let () = expr`
- expressions: integer literals, variables, unary application `f a`
  (left-assoc), `fun x -> e`, `let x = e in e` / `let rec f x = e in e`
  (single self-recursive), `if c then e else e`, `(e)`, `e; e`
- operators: `+ - * / mod`, `= <> < <= > >=`, `&& ||` (short-circuit)
- lists and pairs as builtins (no new syntax): `cons h t`, `nil` (= []),
  `null l`, `hd l`, `tl l`, and `pair a b`, `fst p`, `snd p` — the ONE
  compound datum is the heap cell, exactly Lynn's discipline: his chain
  (`parenthetically → exponentially → …`) runs symbolic programs over a
  uniform heap of two-field cells from the very first rung, with no
  manual allocation in sight. A cons cell or pair compiles to the same
  tag-0 two-field block ML0 tuples and stage-04 list cells use
  (MAKEBLOCK 0 2; `nil` is the integer 0; `hd`/`fst` are GETFIELD), so
  symbolic Λ0 data and ML0 data share one representation and one
  emitted shape.
- strings (read-only): `string_length s`, `string_get s i`, enough to
  define `err_str`
- builtins (fully applied): `arg_count`, `arg_get`, `open_in`,
  `open_out`, `read_byte`, `write_byte`, `close_chan`, `exit`, and
  `err_str "literal"` (string literals appear ONLY there)
- nothing else: no `bytes_*` (rejected by name — the seed keeps bytes
  for the assembler, but they are no longer part of Λ0), no
  strings-as-values/arrays/tuple-syntax/records/ADTs/match/refs, no
  multi-parameter `let f x y`, no partial application of builtins

Functions are unary; multi-argument functions are written as nested
`fun`. The first revision of Λ0 had byte buffers instead of cells, which
forced the compiler into base-28 integer-packed identifiers, byte-pool
allocators and hand-rolled 32-bit registers; v2 replaces all of that
with symbolic data — identifiers are int lists compared recursively,
tables are association lists, and the whole compiler is purely
functional (two passes over the immutable token stream: sizes, then
emission — no backpatching, no mutation). This is the textbook rung.

**Λ1 (data lambda)** — Λ0 plus the machinery a real compiler wants:
string literals as values, `bytes_*` (ml0-compiler is written against
them), `array_*` and `not` builtins, multi-parameter `let f x y = …`
with curried semantics, `()` parameters, and top-level `and` groups.
Still no tuple syntax, ADTs, match, refs or records. ML0's *source*
(the existing `ml0-compiler.ml`) must be Λ1 after removing its two
tuple-lets.

## The new ladder

```
mlc-interp-seed.c    C seed: interprets Λ0 + the assembler's needs
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
