# hcc

`hcc` is the GHC-backed development version of the bootstrap C compiler.

Current status:

- The frontend supports lexing, object-like macro expansion, conditional
  preprocessing, and a small recursive-descent C parser.
- `--check` exercises the frontend directly.
- `--expand-dump` expands includes and command-line defines for the TinyCC
  bootstrap path.
- `-S` emits M1 assembly for the minimal bootstrap assembler path.

The stable call-site goal is:

```sh
hcc -S -o out.M1 [C compiler flags...] input.c
```

The compiler binary intentionally omits development dump modes and `cc`
passthrough so the Blynn/M2 self-hosting path has less generated code to build.
