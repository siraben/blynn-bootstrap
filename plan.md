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

## Current Status

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
- Continue the minimal-bootstrap chain past `gcc46` toward `gccLatest` and
  `gccGlibc` from the HCC-built TinyCC.
