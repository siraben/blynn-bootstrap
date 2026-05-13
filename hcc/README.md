# hcc

`hcc` is the GHC-backed development version of the bootstrap C compiler.

Current status:

- The frontend supports lexing, object-like macro expansion, conditional
  preprocessing, and a recursive-descent C parser for the bootstrap C subset.
- `--check` exercises the frontend directly.
- `--expand-dump` expands includes and command-line defines for the TinyCC
  bootstrap path.
- `--m1-ir` emits HCC's textual M1 IR, which `hcc-m1` lowers to M1 assembly.
- `hcc-m1` emits amd64 and i386 from the shared C lowering file and keeps
  aarch64-specific helpers in `cbits/hcc_m1_arch_aarch64.c`.

The stable call-site goal is:

```sh
hcpp [C compiler flags...] input.c > input.i
hcc1 --m1-ir -o input.hccir input.i
hcc-m1 input.hccir out.M1
```

The compiler binary intentionally omits development dump modes and `cc`
passthrough so the Blynn/M2 self-hosting path has less generated code to build.
Native development builds keep those tools available through the split `hcpp`,
`hcc1`, and `hcc-m1` commands.
