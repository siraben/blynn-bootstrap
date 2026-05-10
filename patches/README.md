# Patch references

This directory records the local deltas against the external source trees used
by the bootstrap.

- `upstreams/blynn-compiler-local.patch`
  - upstream: `https://github.com/blynn/compiler.git`
    at `a1f1c47c9bb3ff6a45a0735ced84984396560535`
  - source compatibility delta for the party -> precisely chain
- `upstreams/tinycc-hcc-bootstrap.patch`
  - upstream: `upstream/janneke-tinycc` at
    `ea3900f6d5e71776c5cfabcabee317652e3a19ee`
  - applied by `nix/tinycc-boot-hcc.nix`
- `upstreams/tinycc-musl-hcc-bootstrap.patch`
  - upstream: `https://repo.or.cz/tinycc.git` at
    `cb41cbfe717e4c00d7bb70035cda5ee5f0ff9341`
  - minimal source fixes for the HCC-built TinyCC musl path
- `blynn-precisely-debug-fail-join.patch`
  - local debug-only patch for the GHC-built `precisely` variant used when
    tracing generated `join`/`fail` code.

The GNU Mes libc reference is generated in `flake.nix` from the pinned GNU Mes
tree plus nixpkgs' minimal-bootstrap Mes source list, rather than carried as a
large generated patch.

Repo-owned bootstrap support files live under `nix/support/`; they are copied
into unpacked source trees during the build instead of embedded in upstream
patch files.

Bootstrap driver scripts are intentionally not carried as upstream patches.
The portable, repo-owned entry points live in `scripts/`.
