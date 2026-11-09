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

HCC splits this work into `hcpp`, `hcc1`, and `hcc-m1`. The TinyCC build
scripts invoke them in order, then use stage0's `M1` and `hex2` to assemble
and link the first compiler. HCC does not provide a MesCC-compatible `-S`
driver.

## Mes libc preparation contract

`scripts/prepare-mes-libc.sh [patched-mes-source [output-directory]]` is shared
by the flake and portable bootstrap. `GNU_MES_DIR` and `OUT_DIR` override those
arguments. The output directory is disposable: preparation replaces it with a
writable source view, architecture headers, startup sources, `libgetopt.c` and
an amalgamated `lib/libc.c`. Callers supply an already patched Mes tree; this
script does not fetch sources or apply patches.

`MES_LIBC_ARCH` selects the **Mes source/header view**, not the HCC target:

| Caller / emitted target | Mes view | Execution contract |
| --- | --- | --- |
| Nix x86_64 Linux / amd64 | x86_64 | Native TinyCC selfhost |
| Nix AArch64 Linux / aarch64 | x86_64 | Intentional LP64 header workaround; separate AArch64 runtime/syscalls |
| Nix RISC-V test / riscv64 | x86_64 | Separate reduced runtime/syscalls, TinyCC under QEMU |
| Portable default / amd64 (alias x86_64) | x86_64 | Selfhost supported |
| Portable aarch64 (alias arm64) | x86_64 | Native stage1 only; selfhost rejected, no cross runner |
| i686 / i386 | Rejected | HCC i386 compilation/smoke is separate and remains available |

Preparation accepts only `MES_LIBC_ARCH=x86_64` (also its default). Previously
`x86` was passed on i686 even though the generated config hardcoded 64 bits,
replacement `strtod.c` requires LP64/binary64, and setjmp is x86_64-specific.
Rejecting that inconsistent view does not assert working 32-bit Mes libc.
Unknown native platforms and TinyCC targets now fail explicitly, rather than
falling back to amd64. Nix TinyCC retains amd64/x86_64, aarch64/arm64 and
riscv64; portable TinyCC retains its narrower target/execution set.

Nix injects absolute paths for `BOOTSTRAP_LIB`, `MES_STRTOD_SOURCE`,
`MES_LDEXP_SOURCE`, `MES_SETJMP_SOURCE` and `MES_CONFIG_SOURCE`. Other callers
normally use the repository defaults; replacement-source overrides must also
be absolute, since amalgamation reads them from inside the output tree.

The upstream source list retains its order, excluding the five replaced
numeric implementations. The replacement strtod and ldexp pair is inserted,
in that order, immediately before the unique `lib/linux/uname.c`. At the
pinned Mes revision this is exactly the old 101st-surviving-entry boundary,
not a floating-point dependency of uname itself. Missing/repeated anchors
fail instead of publishing a newly assembled `libc.c`. Offline fixtures cover
short/reordered lists, exclusions and these failure cases.
