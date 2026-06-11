# CCC Host ML Subset

`ccc/host/ccc_host.ml` is the fast development compiler for CCC, in the same
role that HCC has when developed with GHC: it runs under a full host ML now,
while keeping the implementation close to the compiler source that should later
move into the bootstrapped mini-ML.

The source is OCaml syntax today. Direct Standard ML syntax compatibility is not
the invariant, because datatype declarations, exception declarations, and
entry-point I/O differ between OCaml and SML. The invariant is a small ML
feature set that can be mechanically ported or emitted to either host:

- algebraic datatypes, records, tuples, lists, arrays, refs, exceptions, and
  recursive functions
- explicit parser state and ADT parser replies, not host parser generators
- local helper functions instead of newer OCaml library conveniences
- no modules/functors/classes/objects, labelled or optional arguments,
  pattern guards, `function` shorthand, monadic syntax extensions, OCaml
  bitwise operators, `Buffer`, maps/sets/hashtables, formatting libraries, or
  marshaling/object/runtime libraries

Host-only effects are intentionally small and live at the boundary: command-line
argument parsing, stdin/stdout/stderr, source/output file I/O, environment
lookup for the TinyCC include remap, and opening host include files. A future
SML runner should replace only that boundary while preserving the lexer, parser,
AST, evaluator/lowering, and runtime model. Direct OCaml runtime calls in
`ccc_host.ml` must stay in the small `host_*` wrapper section and carry the
`HOST-ML-BOUNDARY` marker; the compiler body should call those wrappers instead
of `Sys`, channels, stdout, stderr, or `exit` directly.

The development CLI is compiler-shaped:

```sh
nix develop -c ocamlc ccc/host/ccc_host.ml -o /tmp/ccc-host-ocaml
/tmp/ccc-host-ocaml -c input.c -o output.M1
```

With no input file, it still reads C source from stdin and writes M1 to stdout,
which keeps the older pipe-based checks working. `--host-arg ARG` remains
separate from compiler options; it supplies `argv` values to the interpreted C
program's `main`, which is useful when probing TinyCC-shaped sources.

The local guard is:

```sh
nix develop -c ./scripts/check-ccc-host-ml-subset.sh ccc/host/ccc_host.ml
```

The `ccc.host.ocaml` Nix target carries the same grep rule inline, because its
source root is `ccc/` and it cannot depend on repository scripts from that
derivation.
