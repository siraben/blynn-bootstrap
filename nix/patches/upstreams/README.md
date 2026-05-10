# Upstream patch references

This directory records the local deltas against the external source trees used
by the bootstrap.

- `oriansj-blynn-compiler-local.patch`
  - upstream: `https://github.com/OriansJ/blynn-compiler.git`
    at `9e46a8da1df90032f1d270a49a6ef5d0cc909658`, including submodules
  - source compatibility delta for the root compiler chain
- `blynn-compiler-local.patch`
  - upstream: `https://github.com/blynn/compiler.git`
    at `a1f1c47c9bb3ff6a45a0735ced84984396560535`
  - source compatibility delta for the party -> precisely chain
- `tinycc-hcc-bootstrap.patch`
  - upstream: `upstream/janneke-tinycc` at
    `ea3900f6d5e71776c5cfabcabee317652e3a19ee`
  - applied by `nix/tinycc-boot-hcc.nix`

The GNU Mes libc reference is generated in `flake.nix` from the pinned GNU Mes
tree plus nixpkgs' minimal-bootstrap Mes source list, rather than carried as a
large generated patch.

Bootstrap driver scripts are intentionally not carried as upstream patches.
The portable, repo-owned entry points live in `scripts/`.
