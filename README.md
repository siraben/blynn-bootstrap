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
- The current HCC bootstrap support is amd64/x86_64-linux only. The M1 and
  hex2 support files under `hcc/support` are amd64-specific.

## Layout

```text
flake.nix                         # package graph and bootstrap target exports
nix/                              # derivations and bootstrap patches
scripts/                          # portable bootstrap drivers, independent of Nix
hcc/                              # HCC sources and smoke fixtures
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

The repo-owned scripts under `scripts/` mirror the Nix bootstrap stages without
using upstream `go.sh` helpers. They are intended for non-Nix auditing and for
systems where the stage0 tools are already available on `PATH`. The Nix split
stages source the same shell library for common M2 compilation behavior, while
remaining separate derivations so intermediate bootstrap products stay cached.

Minimum requirements:

- POSIX `sh`, `patch`, `sed`, `cp`, `mkdir`, `chmod`, `ln`, and `cat`
- `M2-Mesoplanet` on `PATH`
- initialized upstream checkouts:

```sh
git submodule update --init --recursive
scripts/prepare-upstreams.sh
scripts/bootstrap-blynn-root.sh
METHODICALLY=$PWD/build/blynn-root/bin/methodically scripts/bootstrap-blynn-precisely.sh
```

The default outputs are:

- `build/upstreams`: patched upstream source trees
- `build/blynn-root`: OriansJ/Blynn root chain through `methodically`,
  `crossly`, and `precisely`
- `build/blynn-precisely`: current `blynn/compiler` party chain through
  `precisely_up`

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
