# hcc

`hcc` is the GHC-backed development version of the bootstrap C compiler.

Current status:

- The frontend supports lexing, object-like macro expansion, conditional
  preprocessing, and a small recursive-descent C parser.
- `hcpp` expands includes and command-line defines for the TinyCC bootstrap
  path.
- `hcc1 --check` exercises the frontend directly.
- `hcc1 --m1-ir` emits HCC's textual M1 IR.
- `hcc-m1` lowers HCC's textual IR to stage0 M1 assembly.

The stable call-site goal is:

```sh
hcpp [C compiler flags...] input.c > input.i
hcc1 --m1-ir -o input.hccir input.i
hcc-m1 input.hccir out.M1
```

See [`../docs/hcc-contracts.md`](../docs/hcc-contracts.md) for the pipeline, C subset, HCCIR, target/ABI, and support-file contracts.

The bootstrap-facing toolchain intentionally omits development dump modes,
including the old single-binary `--expand-dump` interface, and `cc` passthrough
so the Blynn/M2 self-hosting path has less generated code to build.
