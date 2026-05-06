# MesCC Scheme Compiler

This directory vendors the Scheme compiler pieces from nixpkgs'
`minimal-bootstrap.mes.srcPost` output for Mes 0.27.1.

## How MesCC Worked

The bootstrap did not run a native C compiler at the first tinycc edge. It ran
Mes, a small Scheme interpreter, and loaded `mescc.scm`:

```sh
mes --no-auto-compile -e main bin/mescc.scm -- [mescc options] input.c
```

`bin/mescc.scm` is the configured command entrypoint generated from
`scripts/mescc.scm.in`. It sets paths such as `MES_PREFIX`, `includedir`, and
`libdir`, then loads the compiler modules under `mescc/`.

The compiler pipeline is:

1. Parse command-line options in `mescc/mescc.scm`.
2. Preprocess C in `mescc/preprocess.scm`.
3. Compile the preprocessed C AST in `mescc/compile.scm`.
4. Lower target-specific operations through `mescc/<arch>/as.scm` and target
   metadata in `mescc/<arch>/info.scm`.
5. Emit M1/hex2-oriented assembly through `mescc/M1.scm` and `mescc/as.scm`.
6. For executable output, invoke the stage0 tools configured by nixpkgs:
   `M1`, `hex2`, and `blood-elf`.

In nixpkgs minimal-bootstrap, the first tinycc edge used it in two steps:

```sh
mes mescc.scm -- -S -o tcc.s ... tcc.c
mes mescc.scm -- -L ... -l c+tcc -o tcc tcc.s
```

The hcc replacement should converge on the same contract: accept C compiler
flags, emit stage0-assembler-compatible output for `-S`, and use the existing
stage0 assemblers/linkers for objects and executables.

## Files

- `bin/mescc.scm`: configured executable entrypoint from nixpkgs.
- `scripts/mescc.scm.in`: upstream template used to generate the entrypoint.
- `mescc/mescc.scm`: option parsing and top-level compiler driver.
- `mescc/preprocess.scm`: C preprocessing.
- `mescc/compile.scm`: C compilation/lowering.
- `mescc/M1.scm`, `mescc/as.scm`: M1/assembly emission support.
- `mescc/x86_64/`: x86_64 lowering metadata and assembler helpers.
