# Upstream patch references

This directory records the local deltas against the external source trees used
by the bootstrap.

- `oriansj-blynn-compiler-local.patch`
  - upstream: `upstream/oriansj-blynn-compiler`
  - local tree: `vendor/blynn-compiler`, excluding its nested `upstream/`
    copy
- `blynn-compiler-local.patch`
  - upstream: `upstream/blynn-compiler`
  - local tree: `vendor/blynn-compiler/upstream`
- `gnu-mes-compiler-reference.patch`
  - upstream: GNU Mes `v0.27.1`, subset rooted at `module/mescc`,
    `module/mescc.scm`, and `scripts/mescc.scm.in`
  - local tree: `vendor/mes-compiler`
- `gnu-mes-libc-reference.patch`
  - upstream: GNU Mes `v0.27.1`, subset rooted at `include/` and selected
    `lib/` files used by the TinyCC bootstrap
  - local tree: `vendor/mes-libc`
- `tinycc-hcc-bootstrap.patch`
  - upstream: `upstream/janneke-tinycc` at
    `ea3900f6d5e71776c5cfabcabee317652e3a19ee`
  - applied by `nix/tinycc-boot-hcc.nix`

