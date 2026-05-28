# blynn-bootstrap

A bootstrap chain that replaces MesCC in nixpkgs' minimal-bootstrap path
with HCC, a C compiler written in Ben Lynn's `precisely` Haskell dialect.

```text
stage0 seeds -> M2-Planet -> Blynn -> HCC -> TinyCC -> GCC
```

HCC has three programs: `hcpp` preprocesses C, `hcc1` emits textual IR, and
`hcc-m1` translates that IR to assembly for stage0's `M1` and `hex2`.

## Build with Nix

On x86_64 Linux:

```sh
nix build .#tinycc.m2.precisely.m2
nix build .#gcc46.m2.precisely.m2
nix build .#gccLatest.m2.precisely.m2
```

TinyCC and GCC 4.6 have built through this path. Later GCC and glibc stages
are exposed as targets, not claimed here as verified end-to-end builds.
The default `nix build` stops at the Blynn compiler stages.

The `m2.precisely.m2` path uses stage0-built M2 for Blynn and HCC. Its HCC
sources are compiled by `crossly1`, which already implements the required
`precisely` dialect; it does not need the later `precisely_up` rebuild.

Debug alternatives are separate targets:

- `tinycc.m2.precisely.gccm2`: GCC-built M2 compiles HCC's generated C.
- `tinycc.m2.precisely.gcc`: GCC compiles HCC's generated C directly.
- `tinycc.host.ghc.native`: GHC compiles HCC's Haskell sources directly.
- `nix develop`: host-built compilers for development and profiling.

These are useful for testing but are not seed-only compiler paths.

## Downstream overlay

`nixpkgsArgs.default` selects the stage0/M2 bootstrap compiler and libc for
nixpkgs' stdenv, while retaining nixpkgs' package expressions:

```nix
let
  system = "x86_64-linux";
  pkgs = import nixpkgs (blynn-bootstrap.nixpkgsArgs.default system);
in pkgs.hello
```

The arguments apply `overlays.default`, exposing this flake's package tree
as `pkgs.blynn-bootstrap` and selecting
`trustRoots.m2.precisely.m2.minimal` as `minimal-bootstrap`. To expose only
the package namespace without replacing stdenv, use `overlays.packages`.
This wiring does not establish an end-to-end downstream build or remove
the host dependencies below.

## Trust boundary

The compiler path is not the entire build environment:

- Stage0 starts with executable `hex0` and `kaem` seeds. Blynn's initial
  combinator programs in `blob/*.source` and `blob/root` are also inputs.
  The VM, packed programs, later compilers, HCC C output, and shared HCC
  object IR are built during the chain rather than imported as binaries.
- Both build interfaces rely on the host kernel and file utilities. Nix
  also uses a host-built BusyBox shell, source fetchers and patch tools;
  some checks use host binutils. This is not a bootstrap of those tools.
- AArch64 and RISC-V TinyCC self-hosting in Nix currently uses host GNU
  `as`/`objcopy` for runtime objects. RISC-V execution uses QEMU. Those
  targets are not equivalent to the x86_64 M2 compiler path.
- TinyCC stage1 uses a limited bootstrap runtime, not a complete libc.
  Some scanning and variadic functions are stubs. The self-built TinyCC
  and its installed libraries are the usable result on x86_64.

Nix compares complete TinyCC stage2/stage3 executables (stage3/stage4 on
AArch64), then compiles and runs test programs. A fixpoint checks stability
under self-compilation; it does not prove C conformance or absence of a
trusting-trust attack. See [tests](tests/README.md).

## Portable build

Run from the repository root on Linux:

```sh
scripts/bootstrap-blynn.sh
# x86_64: also rebuild TinyCC, compare stage2/stage3, and test the result
TINYCC_SELFHOST=1 scripts/bootstrap-blynn.sh
```

Requirements: POSIX `sh`, `patch`, `tar`, `gzip`, `sed`, `find`,
`sha256sum`, ordinary file utilities, and `curl` or `wget` (Git is a
fallback). Self-hosting also requires `cmp`. No host C or Haskell compiler
is needed by the default portable path.

The launcher selects the native architecture; `M2_ARCH` and `M2_OS`
override it. The portable TinyCC stage supports amd64 and AArch64;
self-hosting is wired only for amd64. Nix and portable builds have separate
stage recipes; they do not promise byte-identical final binaries.

By default, `bootstrap-tools.sh` rebuilds from the stage0 seeds and checks
all six exported tools against the upstream answer file. Existing tools
on `PATH` are ignored. To reuse an external toolchain deliberately:

```sh
BOOTSTRAP_TOOLS_FROM_PATH=1 M2LIBC_PATH=/path/to/M2libc \
  scripts/bootstrap-blynn.sh
```

This requires `M2-Mesoplanet`, `M2-Planet`, `blood-elf`, `M1`, `hex2`, and
`kaem` on `PATH`; it does not verify their provenance. The old
`BOOTSTRAP_TOOLS_REBUILD=1` setting still works but is no longer necessary.

Source revisions live in `data/bootstrap-sources.env`. Nix reads the same
Blynn, Mes, and TinyCC revisions, with fixed-output content hashes in its
fetchers. Nix's stage0 pins come separately from `flake.lock`'s nixpkgs.
Both interfaces use the compiler patch series and Mes libc preparation
script. Mes's own `configure-lib.sh` supplies the libc source order.

Portable downloads use revision-addressed HTTPS archives, without Nix's
source-content hash verification. `build/source-cache` is editable; its
`.bootstrap-rev` files are cache tags, not integrity checks. Existing
`upstream/` checkouts are not used implicitly. Set `ORIANSJ_BLYNN_DIR`,
`BLYNN_DIR`, `GNU_MES_DIR`, or `TINYCC_DIR` to use local source overrides.

`scripts/bootstrap-blynn.kaem` lists the stages. Despite the suffix, it is
POSIX shell, not a program for the stage0 kaem interpreter. Each stage can
also be run directly. The default output tree is:

```text
build/source-cache          downloaded upstream sources
build/upstreams             patched sources
build/bootstrap-tools       seed-built tools and stage0 intermediates
build/mes-libc              Mes headers and assembled libc source
build/blynn-root            initial Blynn compiler ladder
build/blynn-precisely       current Blynn compiler ladder
build/hcc-blynn-{sources,objs,c,bin}
build/tinycc-boot-hcc        TinyCC binaries and intermediates
```

The default portable result is stage1 TinyCC; `TINYCC_SELFHOST=1` installs
the self-built compiler, headers, and libraries. `OUT_DIR` changes the
output root. An optional `OUT_DIR/after.kaem` is run with `sh` after the
last stage.

## Layout

- `hcc/`: compiler, runtime, and target support sources.
- `scripts/`: portable stages and benchmark drivers.
- `nix/` and `flake.nix`: derivations and package graph.
- `patches/`: upstream source changes and patch series.
- `tests/`: compiler fixtures and bootstrap regression tests.
- `upstream/`: optional checkouts for refreshing patches.

See [performance tools](docs/performance.md) for measurement commands.

## Credits and license

Ben Lynn's [compiler](https://github.com/blynn/compiler), stage0, and the
bootstrappable.org community provide the underlying bootstrap tools.
GPL-3.0-only; see `LICENSE`.
