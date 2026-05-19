# MLC map to MinCaml

`mlc` follows MinCaml's compiler shape, but changes the target from native
SPARC/PowerPC/x86 assembly to `.mzbc` bytecode for `mzvm`.

References checked while setting this baseline:

- Sumii, *MinCaml: A Simple and Efficient Compiler for a Minimal Functional
  Language* (FDPE 2005).
- `esumii/min-caml` Makefile source list, which names the implementation
  modules in build order.

## Source Language Baseline

Keep the MinCaml constraints that make the compiler auditable:

- strict evaluation
- impure operations
- monomorphic type inference
- higher-order functions through closure conversion
- no polymorphism, modules, or GC in the first bootstrap compiler
- no automatic partial application

CCC-specific changes:

- drop floats and all float-register machinery
- add bytes/string primitives needed by the C compiler
- add real algebraic data types and pattern matching. Source programs should
  use constructors and `match`, not manually encoded tags. The compiler lowers
  typed patterns to decision trees and only then emits constructor tests, field
  extraction, and bytecode branches as a backend detail
- target `.mzbc` stack bytecode, not virtual assembly plus register allocation

## Pass Checklist

The source implementation orders the compiler roughly as:

```text
syntax/parser/lexer
typing
pattern-match lowering
kNormal
alpha
beta
assoc
inline
constFold
elim
closure
virtual
simm
regAlloc
emit
main
```

The `mlc` order should be:

```text
lexer
parser with ADT declarations and pattern syntax
typing
pattern-match compilation
k-normal
alpha
beta
let-flatten
inline
const-fold
elim
closure
mzbc-emit
main
```

Bootstrap split:

- `mlc-interp-seed.c` is the M2-compatible C root. It tree-walks only a small
  core ML. Keep it oriented around variables, literals, lambdas or direct
  functions, application, `if`, `let` / `let rec`, tuples, arrays/bytes, and
  primitive I/O.
- The C root should not be the real ADT or pattern-matching compiler.
  Pattern syntax, constructor declarations, exhaustiveness/refutability
  handling, and decision-tree lowering belong in `mlc.ml`.
- Full mini-OCaml remains a real source language with ADTs and `match`.
  Those features are parsed and lowered by `mlc.byte` after the staged
  bootstrap compiler exists.

Deleted MinCaml stages:

- `virtual`: replaced by direct bytecode selection
- `simm`: SPARC immediate optimization, not relevant to `.mzbc`
- `regAlloc`: stack bytecode has no hardware register file
- native `emit`: replaced by deterministic `.mzbc` serialization

## Current Bootstrap Slice

The checked-in `mlc-interp-seed.c` is the new C bootstrap root. It is a
tree-walking interpreter for a tiny core with `let`, `let rec f x = ...`,
`fun x -> ...`, application, conditionals, arithmetic/comparison, sequencing,
`read_byte`, and `write_byte`. `mlc/stages/00-core.ml` is the first named
stage smoke input and is checked under both host and M2 builds.
`mlc/stages/01-parenthetical.ml` is the first real handoff stage in the style
of Blynn's `parenthetically`: it fully parses a tiny parenthesized MZBC
assembly language and emits a bytecode artifact that the next VM stage can run.
From this stage onward, source-character constants such as delimiters, keyword
letters, whitespace, and the MZBC magic are written as char literals; raw
numbers are reserved for bytecode opcodes, packed metadata, and arithmetic.
The C root also exposes an early `expect_string "..." ch` parser primitive so
handoff stages can consume fixed spellings without long chains of single-byte
expectations. Stage 02 begins the monadic parser transition by spelling parser
steps as `ch -> kon -> result` values and using `parse_bind` to thread the
one-character lookahead state.
The next checked successor, `mlc/stages/03-ast-compiler.ml`, is compiled by
the committed fixed-point `mlc.byte` and deliberately introduces a MinCaml-like
front-end split: parse source into ML ADT nodes, run a small static type check,
then emit VM bytecode. Its first typed core distinguishes `int`, `bool`,
`unit`, `string`, `bytes`, and pair types, with comparisons returning `bool`,
`if` requiring a `bool` guard, string and bytes length forms requiring the
matching block type, indexed reads requiring a string or bytes block plus an
integer index expression, bytes writes requiring an integer byte-value
expression, and pair destructuring checked before field extraction is emitted.
Because the current
compiler cannot yet compile
function-valued parser continuations, stage 03 uses the executable subset of
HCC `ParseLite`: explicit `ParseOk` / `ParseErr` replies, `p_force`,
one-lookahead via `p_peek`, `try`/`need` character and string parsers, and
keyword recognizers, including a `p_try_keyword` / `p_need_keyword` split. Its
expression parser mirrors HCC's precedence-climbing loop by reading an
operator/precedence pair, recursing at the next precedence for the right-hand
side, rebuilding the left-hand side, and continuing the climb. Stage 02
continues to carry the higher-order `p_bind` transition point.
Stage 03 also type-checks sequencing with `;`, requiring the left expression to
have type `unit` before emitting the right expression. Its typed integer core
now covers `read_byte`, literal `write_string`, string literals as immutable
blocks, `String.length` over literal and bound strings, `Bytes.create` with
arithmetic size expressions, `Bytes.length`, `s.[i]`, `b.[i]`, arithmetic
index expressions, `b.[i] <- ch`, arithmetic and char-literal byte-value
expressions, stderr-only `debug_byte` / `debug_string` / decimal `debug_int` /
one-integer `debug_printf`,
raw and escaped char literals, `()`,
`+`, `-`, `*`, `/`, unary `-`, boolean `!`, ML-style `=` plus transitional
`==`, `!=`, `<`, `<=`, `>`, and `>=`, and its program parser accepts
declaration-style top-level `let` and pair destructuring by lowering them to
the same checked expression AST.

The older `mlc-seed.c` is deliberately smaller than the full language and is
now transitional. It is a tiny recursive-descent compiler for `let` bindings,
`if ... then ... else
...`, sequencing with `;`, `read_byte`, `write_byte`, `exit`, integer literals, integer comparisons,
parenthesized arithmetic, `+ - * /`, nested OCaml block comments,
multi-character local identifiers, two-element tuple construction and
destructuring, direct unary `let rec` calls with one `and` partner, runtime-sized `Array.create`,
`Bytes.create`, `Bytes.length` / `String.length`, string literals as immutable byte blocks and direct call arguments, `a.(i)` / `b.[i]` reads and
`a.(i) <- v` / `b.[i] <- v` writes.
It also has a temporary
`write_string "..."` form, including three-digit byte escapes, that lowers
literal bytes to repeated `write_byte` calls. It exists to pin the M2 path,
bytecode writer, expression codegen, and local stack environment before the
real MinCaml-shaped passes are ported into `mlc.ml`.

`02-ml0-compiler.ml` is the staged ML compiler path. In addition to the seed
fixture subset, it now emits first-class unary closures for anonymous
`fun x -> ...` expressions. The VM represents closures as heap blocks with a
bytecode target and a bounded captured stack environment; `APPLY` pushes the
captured values and argument before jumping, and closure bodies return with
`RETURN_FRAME`. Named `let rec` functions can also be passed as first-class
function wrappers while syntactic calls keep the direct `CALL` / `RETURN`
path. Its streaming parser carries one token of lookahead for expression
terminators, so application parsing can distinguish identifier arguments from
`in` / `then` / `else` without relying on first-letter heuristics. Identifier
hashes are kept within the VM's signed 32-bit immediate range so the same
parser logic runs under both the C tree-walking root and self-compiled MZBC.
Its tokenizer, delimiter checks, keyword spelling, and MZBC magic emission use
char literals instead of raw ASCII integers. Stage 02 compiles
`expect_string` calls into ordinary bytecode comparisons and `read_byte`
steps, keeping the primitive out of the VM ABI, and its string parser now goes
through the same `parse_bind` path as later parser combinators.

Treat the current `mlc.ml` as fixed-point self-hosted for the committed
compiler artifact, but not as the final full MinCaml-style compiler yet. It is
written in the seed core language and has a staged one-lookahead
lexer/parser/emitter path for byte literals, escaped char literals, immutable
string byte blocks, `String.length` / `Bytes.length`, local `let`, integer
expressions, nested conditionals, `read_byte`, `Bytes.create`, dynamic byte indexing and
writes, stderr-only `debug_byte` / `debug_string` / decimal `debug_int` /
one-integer `debug_printf`,
imperative `Cell.create` / `Cell.get` / `Cell.set`, record declarations,
record literals up to three fields, field reads, declaration-style top-level `let` /
`let rec`, arbitrary final direct calls, bounded keyword lookahead with capped
identifier hashes, and the first ADT/pattern slice. The `mlc.byte.selfhost`
target compiles `mlc/mlc.ml` with committed `mlc.byte` and compares the result
byte-for-byte with the committed compiler artifact.
Leading `type` declarations build a constructor environment, constructor and
tuple payload expressions allocate VM blocks, tuple destructuring extracts
fields, and simple constructor/wildcard/default-variable `match` forms lower to tag tests and
branches, including multi-declaration, `match-three.ml`,
`match-four.ml`,
`match-bind-default.ml`,
`adt-tuple-payload.ml`, direct tuple payload patterns in
`adt-pattern-tuple.ml`, tuple payload wildcards in
`adt-pattern-tuple-wildcard.ml`, nested tuple payload patterns in
`adt-pattern-nested-tuple.ml`, and recursive `adt-recursion.ml` cases. The next
meaningful step is to extend that ML-side parser/lowerer to recursive and
general decision-tree patterns, then promote the AST/type-checking stage until
it can compile itself and the following compiler source. After that, retire the
transitional direct C bytecode compiler from the critical path.
