# Patch references

This directory records the local deltas against the external source trees used
by the bootstrap.

- `upstreams/blynn-compiler-local.patch`
  - upstream: `https://github.com/blynn/compiler.git`
    at `a1f1c47c9bb3ff6a45a0735ced84984396560535`
  - source compatibility delta for the party -> precisely chain
- `upstreams/tinycc-mescc-source.patch`
  - upstream: `https://repo.or.cz/tinycc.git` at
    `cb41cbfe717e4c00d7bb70035cda5ee5f0ff9341`
  - the same TinyCC source edits used by nixpkgs minimal-bootstrap's MesCC
    TinyCC path; applied by `nix/tinycc-boot-hcc.nix` and by the portable
    `scripts/prepare-upstreams.sh` path when a TinyCC checkout is provided
- `upstreams/tinycc-musl-hcc-bootstrap.patch`
  - upstream: `https://repo.or.cz/tinycc.git` at
    `cb41cbfe717e4c00d7bb70035cda5ee5f0ff9341`
  - minimal source fixes for the HCC-built TinyCC musl path
- `upstreams/musl-hcc-tinycc-va-list.patch`
  - upstream: `https://git.musl-libc.org/cgit/musl` at
    `a9b0b1f2a0c03f1526691fc682db16215ff56834`
  - HCC/TinyCC compatibility for musl's `va_list` handling
- `upstreams/musl-runtime-shell-path.patch`
  - upstream: `https://git.musl-libc.org/cgit/musl` at
    `a9b0b1f2a0c03f1526691fc682db16215ff56834`
  - runtime shell path adjustment used by minimal-bootstrap musl builds
- `upstreams/musl-tinycc-no-plt.patch`
  - upstream: `https://git.musl-libc.org/cgit/musl` at
    `a9b0b1f2a0c03f1526691fc682db16215ff56834`
  - disables PLT-dependent assembly for the TinyCC-built musl path
The GNU Mes libc reference is generated in `flake.nix` from the pinned GNU Mes
tree plus nixpkgs' minimal-bootstrap Mes source list, rather than carried as a
large generated patch.

Repo-owned bootstrap support files live under `nix/support/`; they are copied
into unpacked source trees during the build instead of embedded in upstream
patch files.

Bootstrap driver scripts are intentionally not carried as upstream patches.
The portable, repo-owned entry points live in `scripts/`.
