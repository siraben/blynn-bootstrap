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
- add real algebraic data types and pattern matching, compiling matches to
  constructor tests, field extraction, and bytecode branches
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
parser
typing
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

Deleted MinCaml stages:

- `virtual`: replaced by direct bytecode selection
- `simm`: SPARC immediate optimization, not relevant to `.mzbc`
- `regAlloc`: stack bytecode has no hardware register file
- native `emit`: replaced by deterministic `.mzbc` serialization

## Current Bootstrap Slice

The checked-in `mlc-seed.c` is deliberately smaller than this map. It is now a
tiny recursive-descent compiler for `let` bindings, `if ... then ... else
...`, `write_byte`, integer literals, comparisons, parenthesized arithmetic,
`+ - * /`, nested OCaml block comments, and a narrow `None`/`Some` `match`
form. It exists to pin the M2 path, bytecode writer, expression codegen, local
stack environment, and constructor-tag layout before the real MinCaml-shaped
passes are ported into `mlc.ml`.

Do not treat the current `mlc.ml` as self-hosted. The next meaningful step is
to replace the placeholder with the lexer/parser/type AST spine, including
ADT and pattern nodes, then grow the seed compiler and fixture corpus until
`mlc-seed` can reproduce a committed `mlc.byte`.
