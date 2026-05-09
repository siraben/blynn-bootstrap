# hcc

`hcc` is the GHC-backed development version of the bootstrap C compiler.

Current status:

- The frontend supports lexing, object-like macro expansion, conditional
  preprocessing, and a small recursive-descent C parser.
- `--check` exercises the frontend directly.
- `--expand-dump` expands includes and command-line defines for the TinyCC
  bootstrap path.
- `--m1-ir` emits HCC's textual M1 IR, which `hcc-m1` lowers to M1 assembly.

The stable call-site goal is:

```sh
hcpp [C compiler flags...] input.c > input.i
hcc1 --m1-ir -o input.hccir input.i
hcc-m1 input.hccir out.M1
```

The compiler binary intentionally omits development dump modes and `cc`
passthrough so the Blynn/M2 self-hosting path has less generated code to build.
