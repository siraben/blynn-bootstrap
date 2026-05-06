# blynn-bootstrap

A Nix-based reproduction of the [live-bootstrap](https://github.com/fosslinux/live-bootstrap)
process, but rooted in [blynn-compiler](https://github.com/oriansj/blynn-compiler)
instead of [GNU Mes](https://www.gnu.org/software/mes/).

The aim is to reach a usable Haskell-subset compiler (`precisely`) — and
eventually GCC — starting from a single C file (`vm.c`), with every
intermediate stage expressed as a Nix derivation so the chain is
reproducible and inspectable.

## Status

- `nix build .#blynn-compiler` runs the full bootstrap chain end to end and
  produces `vm`, `pack_blobs`, `marginally`, `methodically`, `crossly`,
  `precisely`, and the intermediate `raw` artifact.
- The current build uses the system C compiler (via stdenv) for the trusted
  parts, matching `vendor/blynn-compiler/Makefile`. Replacing that with the
  M2-Planet + mescc-tools-seed seed (so the trusted binary is a few-hundred-byte
  hex2 program rather than `cc`) is the next milestone and is the live-bootstrap
  parity goal.

## Layout

```
flake.nix                       # entry point
nix/blynn-compiler.nix          # derivation building the vendored bootstrap
vendor/blynn-compiler/          # vendored sources (oriansj fork + M2libc)
```

The vendored sources come from
[oriansj/blynn-compiler](https://github.com/oriansj/blynn-compiler) at commit
`9e46a8d`, with M2libc submodule contents (`ff549d1`) copied in directly.

## Building

```sh
nix build .#blynn-compiler
./result/bin/precisely     # usage: precisely input.hs output.c
```

A `nix develop` shell is provided with `clang`, `make`, and `coreutils`
for hacking on the vendored sources.

## Why oriansj's fork rather than upstream blynn/compiler?

[blynn/compiler](https://github.com/blynn/compiler) is the upstream research
project and moves fast. The oriansj fork has a stabilised bootstrap chain
that was deliberately tuned for M2-Planet compatibility — `vm.c` is rewritten
against `M2libc/bootstrappable.h`, the `.hs` sources use a smaller dialect
(`ffi` rather than `foreign import ccall`, slightly different `Pat`/`Ast`
shapes), and the chain is closed under the dialect each stage parses. That
makes it the right starting point for a bootstrap-from-the-bare-metal effort.

## Updating from upstream

A wholesale sync from `blynn/compiler` is **not** a one-shot operation: the
chain is interdependent — every stage compiles the next, so a syntactic
change in `parity.hs` propagates all the way to `precisely.hs`, and `vm.c`
has to keep accepting whatever ION-assembly variant the chain currently
emits. Concrete update tracks worth pursuing separately:

- **`vm.c`**: oriansj's `vm.c` (845 lines) is a rewritten, M2-Planet-friendly
  superset of upstream's (649 lines). Cherry-picking specific upstream
  improvements (e.g. correctness fixes) is feasible; replacing it wholesale
  would lose the `--raw` / `--rts_c` / `--foreign` machinery the chain
  depends on.
- **`rts.c`**: oriansj's is much larger (328 vs 152 lines) — also non-trivial
  to merge because it's tied to the VM's expectations.
- **`inn/` modules**: upstream factored common code into `inn/Base*.hs`,
  `inn/Ast*.hs`, etc., and added a `party`/`party1`/`party2`/`crossly1`
  staircase between `methodically` and `precisely`. Adopting that would
  modernise the chain and bring in upstream Haskell-feature support, but
  requires the new `.hs` sources to round-trip through the *current*
  `methodically` first.

Until that work happens, treat the vendored sources as a pinned,
known-good snapshot.

## Roadmap

1. ✅ Vendor blynn-compiler + M2libc, build the chain via Nix flake using
   the system C compiler.
2. Plug in `mescc-tools-seed` + `M2-Planet` so `vm` is built from a
   hex2-linked seed binary, not stdenv `cc`.
3. Express each stage (`raw_l`, `raw_m`, ..., `precisely`) as its own Nix
   derivation, à la live-bootstrap, so individual stages can be cached
   and audited.
4. From `precisely`, work toward a Scheme interpreter / TinyCC / GCC,
   replicating the upper layers of live-bootstrap.

## Credits

- Ben Lynn for [blynn/compiler](https://github.com/blynn/compiler).
- The bootstrappable.org community (oriansj et al.) for the M2-Planet-
  compatible fork and tooling.
