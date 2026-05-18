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

Do not treat the current `mlc.ml` as self-hosted. It is now written in the
seed core language and has a tiny lexer/parser/emitter path for byte literals
and one infix addition. The next meaningful step is to grow the staged ML path
from `mlc-interp-seed.c` toward the first real parser/lowerer for ADTs and
patterns, then retire the transitional direct C bytecode compiler from the
critical path.
