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
- `gnu-mes-libc-reference.patch`
  - upstream: GNU Mes `v0.27.1`
    at `c331d801da386ba752f3fe92d0538102a90e988d`
  - local delta for the `include/` and selected `lib/` files used by the
    TinyCC bootstrap
- `gnu-mes-libc-bootstrap-layout.patch`
  - adds the root `lib/crt*.c` and `lib/libgetopt.c` layout consumed by the
    HCC TinyCC bootstrap
- `tinycc-hcc-bootstrap.patch`
  - upstream: `upstream/janneke-tinycc` at
    `ea3900f6d5e71776c5cfabcabee317652e3a19ee`
  - applied by `nix/tinycc-boot-hcc.nix`

Bootstrap driver scripts are intentionally not carried as upstream patches.
The portable, repo-owned entry points live in `scripts/`.
