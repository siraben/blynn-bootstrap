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

## HCCIR target contract

Every new IR file starts with exactly `HCCIR 1` then `T <target>` on the
next line, before any data or function. The frontend defaults to `amd64`;
`hcc1 --target` selects both C type widths and the emitted target (the last
frontend selector wins if repeated). Canonical names are `amd64`, `i386`, `aarch64`, and `riscv64`. CLI and backend metadata
also accept `x86_64`, `x86`, and `arm64` respectively; producers emit canonical
names. i386 has 32-bit pointers/long; the other targets have 64-bit
pointers/long. All have 32-bit int and 64-bit long long.

The backend infers its target from this required record. An explicit
`hcc-m1 --target` is an assertion, **not** permission to reinterpret IR for
another architecture (even one of the same word width). Unknown targets,
extra fields (including word widths), missing, duplicate, or misplaced
records are errors. Legacy header-only IR must be regenerated, even with an
explicit `--target`. Future metadata extensions need a versioned contract;
unknown records are not ignored. Header/target errors are checked before
opening the output. Later malformed IR can leave partial backend output;
frontend lowering errors emit no partial IR, but can leave an empty output
file, as before.

HCC implements the C subset needed for this bootstrap, not a complete C
implementation. It has no host `cc` passthrough. The sources in `support/`
include a limited TinyCC stage1 runtime; they are not a general libc.
