# hcc

`hcc` is the GHC-backed development version of the bootstrap C compiler.

Current status:

- The frontend supports lexing, object-like macro expansion, conditional
  preprocessing, and a small recursive-descent C parser.
- `--check`, `--lex-dump`, `--pp-dump`, and `--parse-dump` exercise that
  frontend directly.
- Normal compiler-driver invocation currently delegates to `cc`. This is the
  temporary backend used to wire the bootstrap away from Mes while native M1
  codegen is implemented.

The stable call-site goal is:

```sh
hcc -o out [C compiler flags...] input.c
```

Once M1 codegen is ready, that command line should remain stable while the
backend stops delegating to `cc`.
