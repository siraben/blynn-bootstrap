# The λ ladder and the C trust root

The first programming language in the chain is a small core λ-calculus. The C
interpreter seed implements only that core and the assembler operations needed
by the first handoff. Strings, arrays, and named-language features are added by
later stages.

The current seed implements the union of the operations used by
`core-lambda.ml` and the assembler. It does not implement the full ML2
language. The canonical chain is the ladder below; ML0 sources run through
`core-lambda` and `data-lambda`, not directly on the C interpreter.

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
  `null l`, `hd l`, `tl l`, and `pair a b`, `fst p`, `snd p`. The only
  compound datum is a two-field heap cell. A cons cell or pair compiles to the same
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
- Diversity anchor: `ml0-compiler` (descended from the same seed via the
  other path during transition, and via Λ1 after cutover) also compiles
  `core-lambda.ml`; the two `.mzbc` must be byte-identical. This replaces
  stage 02's interp-vs-VM anchor as the cross-implementation check.
- `data-lambda` fixpoint at second generation (compiled by core-lambda,
  then by itself once it can — it is written in Λ0 ⊂ Λ1)
- every existing downstream gate (conservative extensions, mltc, ccc1/
  ccpp parity, DDC at M1, tcc self-host fixpoint) is unchanged
- host OCaml: Λ0 and Λ1 are OCaml subsets, so both new stages also run
  under `ocaml` with the existing prelude (crosscheck gate extended)

## Implementation note

The seed retains a small amount of data machinery for the assembler. That
keeps the first handoff compact while leaving the compiler's named-language
features to the staged ML path.

## Performance characteristic (accepted, by design)

`core-lambda`'s self-compile is **O(N²) in the number of top-level
globals**: the global table is a flat `(name, flag)` list and `g_find`
scans it linearly on every variable reference. Measured natively
(`ocamlopt`): compile time is flat in expression *nesting depth* but
quadratic in program *width* (500→4000 globals: 22ms→806ms). On the seed
interpreter this is the chain's most expensive single step
(~31s of the M2-built `lambda ladder + fixpoint` stage; the symbolic
cell heap costs more per operation than the former byte-pool version,
but the O(N²) *shape* is the same in both — it predates the symbolic
rewrite).

The cost is not cleanly reduced while Λ0 stays pure. Every sub-linear
persistent map needs either a recursive sum type (a balanced tree is
`Leaf | Node`) or random access (a hash table needs arrays). Λ0 has
neither: it is lists + tuples + closures, it must also typecheck as host
OCaml (no `-rectypes`, so no equirecursive tree type), and the shrunken
seed has no `match`/`type`. A persistent BST does not fit Λ0: `null t` would
need to distinguish a list from a node tuple, and Λ0 has no sum-type
representation for that distinction.

Λ0 therefore remains pure. The chain accepts this cost, and `core-lambda`
remains lambda plus cons cells with no manual data structures.
