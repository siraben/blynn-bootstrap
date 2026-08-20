# Plan — HCC Bootstrap Path

The goal is to replace the MesCC step in nixpkgs minimal-bootstrap with HCC:

```text
hex0 seed
  -> stage0-posix tools
  -> M2-Planet
  -> Blynn precisely_up
  -> hcpp + hcc1 + hcc-m1
  -> TinyCC
  -> gcc 4.6
  -> later GCC stages
```

## Scope

Goals:

- Produce an auditable HCC replacement for the MesCC-to-TinyCC edge.
- Preserve the stage0/M2 ancestry through the faithful `m2.precisely.m2` path.
- Keep faster host/GCC-built paths available only as debug and comparison aids.

Non-goals:

- HCC is not intended to be a complete hosted C compiler.
- Debug paths are not accepted substitutes for the faithful bootstrap path.
- Exporting a flake attr is not the same as accepting that stage as complete.

## Current Status

Status words used here:

- Wired: the attr or script path exists.
- Built: it has completed through the HCC path.
- CI-gated: CI builds it or explicitly evaluates its documented attr.
- Accepted: complete for the current HCC audit scope.

- `precisely_up` is available through both the full stage0/M2 path and faster
  GCC-built debug paths.
- HCC is split into auditable phases:
  - `hcpp`: include expansion and preprocessing.
  - `hcc1`: lex, parse, lower, and emit M1 IR.
  - `hcc-m1`: write M1 assembly from HCC's textual IR.
- `tinycc.m2.precisely.m2` builds TinyCC through the stage0-built
  `precisely_up` and HCC path.
- `gcc46.m2.precisely.m2` builds successfully from the HCC-built TinyCC.
- Follow-on minimal-bootstrap targets are wired:
  - `gcc46Cxx`
  - `gcc10`
  - `gccLatest`
  - `glibc`
  - `gccGlibc`

| Stage | Wired | Built | CI-gated | Accepted |
| --- | --- | --- | --- | --- |
| HCC tools from `m2.precisely.m2` | yes | yes, through TinyCC | yes, via stage0 TinyCC and M1 smoke builds | yes |
| `tinycc.m2.precisely.m2` | yes | yes | yes, built on amd64 | yes |
| `gcc46.m2.precisely.m2` | yes | yes | drvPath evaluated on amd64 | yes |
| Later minimal-bootstrap attrs | yes | not claimed here | selected README attrs are evaluated on amd64 | no |
| `m2.precisely.gccm2` debug attrs | yes | yes for fast iteration targets | selected attrs evaluated/built | debug only |

## Useful Targets

```sh
nix build .#tinycc.m2.precisely.m2
nix build .#gcc46.m2.precisely.m2
nix build .#gccLatest.m2.precisely.m2
```

Faster debug path:

```sh
nix build .#tinycc.m2.precisely.gccm2
nix build .#gccLatest.m2.precisely.gccm2
```

Development checks:

```sh
nix build .#hcc.host.ghc.native .#tests.smoke.m1 .#tests.mescc
```

## Near-Term Work

- Keep HCC source small enough for the stage0-built `precisely_up` path.
- Preserve byte-identical TinyCC M1 output for cleanup and refactor-only
  changes.
- Use the fast GHC and GCC/M2 debug paths for performance work before
  repeating full stage0 builds.
- Build, gate, and accept the minimal-bootstrap chain past `gcc46` toward
  `gccLatest` and `gccGlibc` from the HCC-built TinyCC.
