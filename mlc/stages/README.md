# MLC Bootstrap Stages

The mini-OCaml bootstrap follows the same shape as Ben Lynn's staged compiler:
each step is named, has explicit input sources, and is produced by the previous
step rather than by a monolithic all-powerful seed.

Current stages:

- `mlc-interp-seed.c` is the M2-compatible C root. It is a tree-walking
  interpreter for the small core language used to bootstrap later ML stages.
- `00-core.ml` is the first checked core-language input for that root. It
  exercises closures, recursive functions, conditionals, arithmetic, and byte
  output.

Planned stages:

- `01-parser.ml` grows the ML-side parser for the real source language.
- `02-patterns.ml` adds ADT and pattern-match lowering in ML, not in C.
- `03-bytecode.ml` emits MZBC and replaces the transitional direct C bytecode
  compiler for normal bootstrap use.
