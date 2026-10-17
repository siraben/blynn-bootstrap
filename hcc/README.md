# HCC

HCC is a bootstrap C compiler. Its Haskell frontend is compiled by Blynn;
GHC builds are available for development. The M1 backend and runtime
support are written in C and compiled by M2 on the bootstrap path.

```sh
hcpp [preprocessor flags...] input.c > input.i
hcc1 --m1-ir -o input.hccir input.i
hcc-m1 input.hccir out.M1
```

`hcpp` expands includes and macros. `hcc1` parses and lowers preprocessed C;
`--check` stops after frontend checks. `hcc-m1` emits target assembly for
stage0's `M1` and `hex2`, not a host assembler. Target support covers amd64,
i386, AArch64, and RISC-V64, with different bootstrap coverage; see the
[top-level README](../README.md) and [tests](../tests/README.md).
The [contract reference](../docs/hcc-contracts.md) describes the C subset,
HCCIR encoding, target ABI, and support-file layering.

HCC implements the C subset needed for this bootstrap, not a complete C
implementation. It has no host `cc` passthrough. The sources in `support/`
include a limited TinyCC stage1 runtime; they are not a general libc.
