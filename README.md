# blynn-bootstrap

A Nix bootstrap chain that replaces the MesCC edge in nixpkgs'
minimal-bootstrap path with `hcc`, a C compiler written in Blynn's
`precisely` Haskell dialect.

The goal is an auditable path from the stage0 seed tools to TinyCC and then
through the usual minimal-bootstrap GCC chain.

## Status

- `precisely_up` is built from the Blynn bootstrap chain, including a
  stage0/M2-Planet path.
- `hcc` is split into `hcpp`, `hcc1`, and `hcc-m1`. `hcpp` preprocesses C,
  `hcc1` lowers preprocessed C to M1 IR, and `hcc-m1` writes M1 assembly for
  the stage0 `M1`/`hex2` tools.
- `tinycc.m2.precisely.m2` builds TinyCC through the stage0-built
  `precisely_up` and HCC path.
- `gcc46.m2.precisely.m2` has built successfully from the HCC-built TinyCC.
- The rest of nixpkgs' minimal-bootstrap chain is exposed as flake targets:
  `gcc46Cxx`, `gcc10`, `gccLatest`, `glibc`, and `gccGlibc`.
- HCC emits stage0 M1 for amd64 and i386 smoke targets. The full TinyCC
  bootstrap path is still wired for amd64.

## Layout

```text
flake.nix                         # package graph and bootstrap target exports
nix/                              # derivations and bootstrap patches
scripts/                          # portable bootstrap drivers, independent of Nix
hcc/                              # HCC sources and smoke fixtures
hcc/*.modules                     # ordered source manifests for Blynn stages
tests/                            # HCC and MesCC reference tests
upstream/                         # pinned upstream mirrors used to refresh patches
```

## Building

```sh
nix build .#tinycc.m2.precisely.m2
nix build .#gcc46.m2.precisely.m2
nix build .#gccLatest.m2.precisely.m2
```

For faster iteration, use the GCC-built M2-Planet debug path:

```sh
nix build .#tinycc.m2.precisely.gccm2
nix build .#gccLatest.m2.precisely.gccm2
```

`nix develop` provides the GHC-built HCC tools for local profiling and
byte-for-byte output checks. Upstream Blynn and Mes sources are fetched by
fixed-output derivations and patched with `patches/upstreams`.

## Portable Bootstrap

The repo-owned scripts under `scripts/` are the primary bootstrap interface.
They do not depend on Nix and avoid upstream `go.sh` wrappers. Nix derivations
wrap the same source pins and, for HCC binary construction, the same portable
script, so Nix is an orchestration/cache layer rather than the only description
of the build.

Shared source pins live in `data/bootstrap-sources.env`. The portable scripts
source that file directly, and `flake.nix` parses the same file. Patch files
under `patches/upstreams/` are applied by the portable source-prep stage and by
the matching Nix stages.

Host environment requirements:

- POSIX `sh`
- `patch`, `tar`, `gzip`, `sed`, `find`, `cp`, `mkdir`, `chmod`, `ln`, `rm`,
  `mv`, and the usual POSIX file utilities
- `curl` or `wget` for pinned source archives; `git` is only a fallback

If `M2-Mesoplanet`, `M2-Planet`, `M1`, `hex2`, and `kaem` are already on
`PATH`, the tool bootstrap stage links those into `build/bootstrap-tools`.
Otherwise it fetches the pinned `stage0-posix` source, runs the architecture
seed from hex0, checks the stage0 answer file, and copies the resulting tools
from the stage0 output. Set `BOOTSTRAP_TOOLS_REBUILD=1` to force rebuilding
those tools from the seed.

The full portable path is:

```sh
scripts/bootstrap-blynn.sh
```

On a fresh Alpine-style image with `wget`, this builds the default amd64 path
from the branch archive without requiring `git`:

```sh
apk add --no-cache ca-certificates wget patch && cd /tmp && wget -qO- https://github.com/siraben/blynn-bootstrap/archive/refs/heads/portability.tar.gz | tar xz && cd blynn-bootstrap-portability && M2_ARCH=amd64 M2_OS=Linux sh scripts/bootstrap-blynn.sh && test -x build/tinycc-boot-hcc/bin/tcc
```

If you are preparing the TinyCC source used by the HCC bootstrap outside Nix,
pass the same TinyCC checkout to `prepare-upstreams.sh`; it applies
`patches/upstreams/tinycc-mescc-source.patch`, the same patch used by
`nix/tinycc-boot-hcc.nix`:

```sh
TINYCC_DIR=$PWD/upstream/tinycc scripts/prepare-upstreams.sh
```

`scripts/bootstrap-blynn.sh` is only a launcher. The auditable stage transcript
is `scripts/bootstrap-blynn.kaem`, following the stage0 convention of a linear
command file with plain environment variables, `${VAR}`/`${VAR:-fallback}`
expansion, and an optional `build/after.kaem` continuation hook. It is written
for a POSIX `sh` environment while keeping the top-level transcript close to
stage0's kaem style.

The default outputs are:

- `build/source-cache`: pinned source clones, including `stage0-posix`
- `build/upstreams`: patched upstream source trees
- `build/bootstrap-tools/bin`: `M2-Mesoplanet`, `M2-Planet`, `M1`, `hex2`,
  and `kaem` built from the stage0-posix hex0 seed, unless existing tools were
  linked from `PATH`
- `build/mes-libc`: patched/generated GNU Mes libc view for TinyCC
- `build/blynn-root`: OriansJ/Blynn root chain through `methodically`,
  `crossly`, and `precisely`
- `build/blynn-precisely`: current `blynn/compiler` party chain through
  `precisely_up`
- `build/hcc-blynn-sources`: single-stream Blynn inputs assembled from
  `hcc/hcpp.modules` and `hcc/hcc1.modules`
- `build/hcc-blynn-c`: C generated from those HCC Blynn inputs
- `build/hcc-blynn-bin/bin`: `hcpp`, `hcc1`, and `hcc-m1`
- `build/tinycc-boot-hcc/bin`: HCC-built TinyCC

The portable TinyCC stage defaults to the HCC-linked stage1 `tcc`, which is the
minimal end-to-end bootstrap artifact. Set `TINYCC_SELFHOST=1` to attempt the
stage2/stage3 TinyCC self-hosting pass.

Stage scripts that compile code keep intermediate files in `artifact/` beside
their `bin/` output, matching stage0's audit layout.

Each stage can also be run directly:

```sh
scripts/prepare-upstreams.sh
scripts/bootstrap-tools.sh
PATH=$PWD/build/bootstrap-tools/bin:$PATH scripts/prepare-mes-libc.sh
PATH=$PWD/build/bootstrap-tools/bin:$PATH M2LIBC_PATH=$PWD/build/bootstrap-tools/artifact/stage0-posix/M2libc scripts/bootstrap-blynn-root.sh
METHODICALLY=$PWD/build/blynn-root/bin/methodically PATH=$PWD/build/bootstrap-tools/bin:$PATH scripts/bootstrap-blynn-precisely.sh
scripts/hcc-blynn-sources.sh
PRECISELY_UP=$PWD/build/blynn-precisely/bin/precisely_up scripts/hcc-blynn-c.sh
PATH=$PWD/build/bootstrap-tools/bin:$PATH M2LIBC_PATH=$PWD/build/bootstrap-tools/artifact/stage0-posix/M2libc scripts/hcc-blynn-bin.sh
PATH=$PWD/build/bootstrap-tools/bin:$PATH M2LIBC_PATH=$PWD/build/bootstrap-tools/artifact/stage0-posix/M2libc scripts/tinycc-boot-hcc.sh
```

Use `M2_ARCH` and `M2_OS` to select the M2libc target, matching the stage0
tooling convention used by nixpkgs' minimal-bootstrap. For example:

```sh
M2_ARCH=amd64 M2_OS=Linux scripts/bootstrap-blynn.sh
```

## Credits

- Ben Lynn for [blynn/compiler](https://github.com/blynn/compiler).
- The bootstrappable.org community for stage0 and minimal-bootstrap tooling.

## License

GPL-3.0-only. See `LICENSE`.
