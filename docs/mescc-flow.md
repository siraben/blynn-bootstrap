# MesCC Scheme Compiler Flow

This records the MesCC compiler path that HCC is replacing in the bootstrap.
The source of truth for build-time path injection is nixpkgs'
`pkgs/os-specific/linux/minimal-bootstrap/mes/default.nix`.

MesCC did not run a native C compiler at the first TinyCC edge. It ran Mes, a
small Scheme interpreter, and loaded the configured MesCC entrypoint:

```sh
mes --no-auto-compile -e main bin/mescc.scm -- [mescc options] input.c
```

`bin/mescc.scm` is generated from upstream `scripts/mescc.scm.in` during the
Mes derivation. Build-specific paths such as the Mes prefix, include directory,
library directory, `M1`, `hex2`, `blood-elf`, and `srcdest` are substituted by
the derivation after unpacking. They should not be committed in patch files.

The compiler pipeline is:

1. Parse command-line options in `mescc/mescc.scm`.
2. Preprocess C in `mescc/preprocess.scm`.
3. Compile the preprocessed C AST in `mescc/compile.scm`.
4. Lower target-specific operations through `mescc/<arch>/as.scm` and target
   metadata in `mescc/<arch>/info.scm`.
5. Emit M1/hex2-oriented assembly through `mescc/M1.scm` and `mescc/as.scm`.
6. For executable output, invoke stage0 tools configured by the derivation:
   `M1`, `hex2`, and `blood-elf`.

In nixpkgs minimal-bootstrap, the first TinyCC edge used it in two steps:

```sh
mes mescc.scm -- -S -o tcc.s ... tcc.c
mes mescc.scm -- -L ... -l c+tcc -o tcc tcc.s
```

The HCC replacement should preserve that contract: accept C compiler flags,
emit stage0-assembler-compatible output for `-S`, and use the existing stage0
assemblers/linkers for objects and executables.
