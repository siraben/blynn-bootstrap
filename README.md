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

## Layout

```text
flake.nix                         # package graph and bootstrap target exports
nix/                              # derivations and bootstrap patches
vendor/blynn-compiler/            # Blynn compiler sources used for precisely
vendor/hcc/                       # HCC sources and smoke fixtures
vendor/nixpkgs-minimal-bootstrap/ # pinned minimal-bootstrap package set
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
byte-for-byte output checks.

## Credits

- Ben Lynn for [blynn/compiler](https://github.com/blynn/compiler).
- The bootstrappable.org community for stage0 and minimal-bootstrap tooling.
