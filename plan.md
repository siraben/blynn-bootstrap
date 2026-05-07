# Plan C — Replace Mes/MesCC with a Haskell-subset C compiler

The endgame: `tinycc-bootstrappable` builds from the 181-byte `hex0-seed`
with **zero Mes/MesCC, zero stdenv cc, zero Scheme**, going through
`precisely` instead of `mescc.scm` as the bootstrappable C-compiler
substrate.

## What we already have

- The 181-byte hex0-seed is in nixpkgs minimal-bootstrap, fully described.
- `stage0-posix` builds hex0 → hex1 → hex2 → M0 → cc_x86 → M1 →
  blood-elf → kaem → M2-Planet from that seed, with no Mes.
- Oriansj's `blynn-compiler` builds `vm`, `pack_blobs`, then runs the
  bootstrap chain to `precisely`, *also* without Mes — using M2-Planet
  for `vm.c`/`pack_blobs.c`, then the chain self-bootstraps.
- We have `precisely_up` from upstream blynn/compiler, fixpointed.
  It accepts a strictly larger Haskell dialect than orians' `precisely`.

## Current status as of 2026-05-07

- `vendor/hcc` is no longer a stub. The GHC development build has a
  lexer, preprocessor, parser, lowering, and M1 emitter for the C subset
  currently needed by the smoke corpus and the TinyCC bootstrap probe.
- `nix build .#hcc-ghc .#hcc-m1-smoke .#hcc-mescc-tests` is green.
  The M1 smoke runner is a Python script with each fixture in its own C
  file under `vendor/hcc/test/m1-smoke/examples/`.
- hcc-generated M1 can be assembled by nixpkgs minimal-bootstrap's
  `stage0-posix.mescc-tools` (`M1` + `hex2`) for the smoke corpus.
- A GHC-built hcc can compile a pre-expanded TinyCC one-source input to
  M1. Assembled through `M1`/`hex2`, that produces a TinyCC binary that
  compiles TinyCC's one-source `tcc.c` to an ELF object.
- That hcc-built TinyCC object links with the temporary freestanding
  development harness and runs. With `TCC_MUSL=1`, TinyCC's own
  `include/stdarg.h` first in the include path, and `lib/va_list.c`
  linked, the resulting compiler compiles TinyCC again; the third
  generation also links and compiles a smoke object.
- `tinycc-boot-hcc` now builds TinyCC through `hcc --expand-dump`,
  `hcc -S`, `M1`, and `hex2`; it no longer invokes MesCC or hcc's
  backend C compiler path. The resulting binary runs `-version` and
  compiles a no-include C smoke file. The next blocker for making it a
  drop-in downstream `tcc` is quoted include handling in the hcc-built
  TinyCC: it currently opens the containing directory for a simple
  `#include "header.h"` smoke instead of opening the header file itself.

The immediate remaining work is to replace the `/tmp` TinyCC self-host
probe with a reproducible derivation: generate or vendor the guarded
one-source TinyCC input, run `hcc -S`, assemble with `M1`, link with
`hex2`, include the minimal runtime objects (`tcc-bootstrap-support`,
TinyCC `lib/va_list.c`, start/syscall/memory support), then run the
TinyCC-to-TinyCC self-host check in Nix.

The remaining gap: **MesCC compiles tinycc.c**. To remove Mes, we need
something else that compiles tinycc.c. That something must itself be
buildable from `precisely`, i.e. written in the Haskell-subset that
`precisely_up` accepts.

We'll call this compiler **`hcc`** ("Haskell-bootstrap C compiler").

## Non-goals

- Replacing tinycc with our own C compiler in production. `hcc` only
  needs to compile **tinycc-bootstrappable**'s specific source tree.
  Once tinycc is built, the rest of the chain (musl, gcc46, gcc-latest,
  the world) uses tinycc → gcc.
- Producing optimal code. `hcc` output can be slow and large; tinycc-
  bootstrappable is small and we only run it once.
- Targeting anything but `x86_64-linux` initially. i686/aarch64 come
  later.
- Self-hosting `hcc` itself. `hcc` is written in Haskell-subset and
  compiled by `precisely`; it doesn't need to compile itself.

## Constraints

- **Source dialect**: `hcc` source must parse with `precisely_up` (or
  be downgradeable to it). That means: no GADTs, no type families, no
  RankNTypes, no view patterns. ADTs, type classes (single-param),
  monads, records — all fine.
- **Runtime**: precisely emits a SKI-reduction C runtime. Compilation
  of large programs is slow (seconds-to-minutes) and memory-heavy.
  `hcc` will likely take minutes to compile tinycc; that's acceptable
  for a one-shot bootstrap stage.
- **Output format**: emit M1 assembly text consumable by stage0-posix's
  `M1` assembler (and then `hex2` linker). This avoids needing an ELF
  emitter or a linker — both are already in stage0-posix and work
  byte-for-byte deterministically.

## Bootstrap chain we're targeting

```
hex0-seed (181 B blob)
  └── stage0-posix → hex0 hex1 hex2 M0 cc_x86 M1 blood-elf kaem M2-Planet
                     mescc-tools (unchanged from nixpkgs)
  └── M2-Planet compiles vm.c, pack_blobs.c
        └── vm runs bootstrap chain → singularity → ... → barely → effectively
              → lonely → patty → guardedly → assembly → mutually → uniquely
              → virtually → marginally → methodically → crossly → precisely
              → party → multiparty → party1 → party2 → crossly_up → crossly1
              → precisely_up
              └── precisely_up compiles hcc.hs → hcc.c
                    └── (compiled with tinycc-bootstrappable? circular.)
```

The bootstrap circularity at the bottom: `hcc` needs *some* C compiler
to turn `hcc.c` into a binary. Options:

1. **M2-Planet compiles hcc.c directly.** `hcc.c` is precisely's output,
   which is plain C with structs, function pointers via integer indices,
   no varargs except `printf`-style. M2-Planet handles this in similar
   shape for the `vm.c`/`pack_blobs.c`/orians-`marginally.c` already.
   Likely workable for `hcc.c` if we keep the source simple.
2. **An earlier bootstrap stage compiles hcc.c.** orians' `methodically`
   (which lives at C-output level too) is already cc-compiled in our
   chain via M2-Planet. So if `hcc.c` is M2-Planet-compatible, we're
   fine with option 1.
3. **`hcc` is bootstrapped from `vm` directly**, without going through
   the full party→precisely chain. Cheaper but harder to maintain.

We pick **option 1**: `hcc.c` is M2-Planet-compiled. This means
`precisely_up`'s C output must stay within M2-Planet's accepted subset
**when compiling hcc**. We may need to special-case hcc's source to
avoid features precisely_up emits that M2-Planet rejects (e.g. char
literals in initialisers, some pointer arithmetic). Worst case: we
add a small `precisely_up`-output post-processor.

## Phases

### Phase 0 — Scaffolding (this session)

**Deliverables:**
- Vendor nixpkgs `stage0-posix/` into `vendor/nixpkgs-minimal-bootstrap/`.
- Vendor nixpkgs `tinycc/` (sources only, not the whole derivation) so
  we know exactly which C source we have to compile.
- Vendor `mescc-tools-extra` and `kaem` derivation files.
- Survey what C features tinycc-bootstrappable's source uses (so we
  know what `hcc` must accept). Save as `phase0-survey.md`.
- Stand up `vendor/hcc/` with a stub `Main.hs` that compiles via
  `precisely_up` and prints "hcc: no input files" to stderr. Wire
  into `flake.nix` as `packages.hcc-stub`.

**Exit criteria:** `nix build .#hcc-stub` produces a binary, run it,
get the message. Confirms the precisely_up → cc → executable pipeline
works for arbitrary new sources, not just the bootstrap chain.

### Phase 1 — C lexer + minimal preprocessor

**Deliverables:**
- `vendor/hcc/Lexer.hs`: tokenises the C tinycc uses. Tokens: idents,
  integer/char/string literals, punctuation, all C operators. Comments
  (block + line), trigraphs (skip — tinycc doesn't use them).
- `vendor/hcc/Preprocessor.hs`: handles `#include`, `#define` (object
  + function-like), `#if`/`#ifdef`/`#ifndef`/`#else`/`#elif`/`#endif`,
  `#undef`, `#error`, `#line` (passthrough), `#pragma` (passthrough).
  Macros are expanded textually. No support for `__VA_ARGS__` until
  we see tinycc actually need it (it might not).
- A `tools/lex-dump` mode: read C, print token stream — for debugging.

**Test corpus:**
- `mes-libc/lib/libc.c` and `crt1.c` (small, well-defined).
- A handful of files from `tinycc-bootstrappable/`: `tcc.h`,
  `libtcc.c` first 200 lines.
- Round-trip test: `unlex(lex(x)) == normalise(x)` for a small
  sample of files (whitespace-insensitive comparison).

**Exit criteria:** for the test corpus, lexer+preprocessor produces
the same token stream as gcc's `cpp -E | strip-comments`, modulo
whitespace.

### Phase 2 — C parser → typed AST

**Deliverables:**
- `vendor/hcc/Ast.hs`: ADTs for `Decl`, `Stmt`, `Expr`, `Type`,
  storage classes, type qualifiers.
- `vendor/hcc/Parser.hs`: recursive-descent parser. Coverage:
  - All declarators (function, array, pointer, qualified).
  - Struct/union/enum (including forward decls).
  - Typedefs (with the lexer hack: parser feeds typedefs back into
    lexer so that typedef'd names tokenise as type names).
  - Function definitions including K&R-style argument lists if
    tinycc uses them (need to check during Phase 0 survey).
  - Initialiser lists (designated initialisers if tinycc uses them).
  - All C statements including `goto`, `switch`/`case`, `do`/`while`,
    compound literals.
  - All C expressions including ternary, comma, sizeof, casts,
    compound assignment, post/pre inc/dec.
- `tools/parse-dump`: parse C, pretty-print AST.

**Test corpus:** as Phase 1 plus `tinycc-bootstrappable/{libtcc,tccgen,
tccelf,tccpp,x86_64-gen,i386-asm,tcc}.c`.

**Exit criteria:** parses every file in tinycc-bootstrappable's
build set without error.

### Phase 3 — Type checker + IR lowering

**Deliverables:**
- `vendor/hcc/Typer.hs`: resolves identifiers to declarations, infers
  types of expressions, validates lvalues, applies integer promotions
  and usual arithmetic conversions, lays out structs (with x86_64
  alignment rules), enforces (some) constness.
- `vendor/hcc/Ir.hs`: a low-level IR. Roughly: SSA-free three-address
  code over typed temps. Each function is a list of basic blocks; each
  block is a list of `Op` (assign, load, store, binop, cmp, branch,
  call, ret) terminating in a control-flow op.
- `vendor/hcc/Lower.hs`: AST → IR. Handles short-circuit `&&`/`||`,
  ternary, switch (lowered to chained branches initially; jump tables
  later if needed), break/continue (label management), return, sizeof
  (constant-fold), array indexing → pointer arith, struct field
  access → load with offset, function pointers (just an integer-typed
  variable in IR; codegen handles indirect call).

**Test corpus:** add `assert` macros to existing test programs;
typecheck must accept all of them.

**Exit criteria:** every tinycc-bootstrappable source file lowers to
IR without error. Pretty-printed IR is human-readable and traceable
back to source lines (`tools/ir-dump`).

### Phase 4 — Codegen to M1 assembly

**Deliverables:**
- `vendor/hcc/CodegenX86_64.hs`: lower IR to M1 assembly text. Output
  is the format `M1` understands (the same format M2-Planet emits).
- Calling convention: System V AMD64 ABI for tinycc compatibility.
  First six int args in `rdi rsi rdx rcx r8 r9`; rest on stack. Return
  in `rax`. Caller-cleaned. Sufficient for tinycc, which is plain C.
- Register allocation: stack-based initially. Every IR temp gets a
  stack slot; ops load to fixed scratch regs, compute, store back.
  Simple, slow, correct. Future: linear-scan if we need speed.
- Globals: emitted as M1 `.data`/`.rodata`-style sections; M1 + hex2
  produce the ELF.
- Strings: deduplicate; emit in `.rodata`.
- Static-storage initialisers: lowered to byte sequences (with
  relocations for pointers — rely on M1's absolute-address support).
- Floats: skip until we hit them. tinycc-bootstrappable mostly avoids
  floats; if it doesn't, we add SSE codegen later.

**Test corpus:** one-function programs of increasing complexity:
`return 42`, `add`, `factorial`, `strlen`, `memcpy`, `qsort` of ints,
`malloc`+`free` against a tiny static heap. Compare output binary's
runtime against the same source compiled by gcc.

**Exit criteria:** all of the above test programs produce identical
runtime behaviour to gcc-compiled versions. Linking goes via M1 +
hex2 + blood-elf, no `ld`/`ld.bfd` involved.

### Phase 5 — Hello-world & full smoke tests

**Deliverables:**
- A `nix build .#hcc-tests` derivation that:
  1. Builds `hcc` (via `precisely_up` → `hcc.c` → M2-Planet → `hcc`).
  2. Runs `hcc` on each test program.
  3. Pipes hcc output through M1, hex2, blood-elf to ELF.
  4. Runs the ELF; captures stdout/exit code.
  5. Compares to gcc baseline.
- Test programs: hello world, fizzbuzz, hashmap, an actual `cat`
  implementation, a tiny tar-extractor (links against mes-libc).

**Exit criteria:** all smoke tests green in CI.

### Phase 6 — Compile M2-Planet

**Why this stage:** M2-Planet is small (~5k LoC), already
bootstrappable, and very vanilla C. If `hcc` can't compile M2-Planet,
it sure as hell can't compile tinycc.

**Deliverables:**
- `nix build .#m2-planet-via-hcc` — M2-Planet binary built from
  M2-Planet source by `hcc`.
- Verify: this M2-Planet compiles `vm.c` to the same bytes as the
  hex0-seeded M2-Planet. Reproducibility check.

**Exit criteria:** byte-identical M2-Planet binary, or M2-Planet that
produces byte-identical `vm` and `pack_blobs` outputs.

### Phase 7 — Compile tinycc-bootstrappable

**The endgame.** Iterate on `hcc` features as tinycc's source
demands them. Expected pain points:

- **Bitfields**: tinycc has them. Layout is implementation-defined;
  we need to match what tinycc itself expects (since tinycc's source
  parses tinycc's headers).
- **`__attribute__((...))`**: just parse-and-ignore for nearly all,
  but `noreturn` and `aligned` may need real handling.
- **`__builtin_*`**: need to provide builtins or rewrite tinycc to
  not use them.
- **VLAs**: tinycc's source seems to use them; we may need to lower
  to alloca, or patch tinycc-bootstrappable to use malloc (live-
  bootstrap already does this — see the `_onstack` patch in
  `bootstrappable.nix`).
- **Inline assembly**: tinycc may have `__asm__` blocks. Skip with
  patch if minor; otherwise emit raw M1 from the asm string (parse
  AT&T syntax → M1).
- **`setjmp`/`longjmp`**: handled at libc level, but our codegen
  must respect callee-saved registers correctly.

**Deliverables:**
- `nix build .#tinycc-via-hcc` — tinycc-bootstrappable binary, built
  from the same C sources as nixpkgs `tinycc-bootstrappable` but with
  `hcc` replacing MesCC. Mes never enters this derivation's input
  closure.
- Run `tinycc-via-hcc -version`. Run it on hello-world.

**Exit criteria:** `tinycc-via-hcc` self-compiles its own source and
the result is byte-identical (or "diverse double compile"-equivalent)
to `tinycc-bootstrappable`.

### Phase 8 — Wire into nixpkgs minimal-bootstrap

**Deliverables:**
- Vendored, modified copy of nixpkgs minimal-bootstrap where the
  `tinycc-bootstrappable` derivation depends on `hcc` (and through
  it on `precisely_up`, `methodically`, `vm`, M2-Planet, hex0-seed)
  rather than on `mes`.
- The `mes/` directory is *removed from the dependency closure* of
  `tinycc-bootstrappable`. (`mes` may still build for comparison;
  what matters is that `nix-store --query --tree
  $(nix-build -A tinycc-bootstrappable)` no longer mentions Mes.)
- Downstream derivations (`tinycc-mes`, `musl-tcc`, `gcc46`, ...)
  rebuild on top of `tinycc-via-hcc` unchanged, modulo wiring.
- A `bootstrap-tree.dot` showing the new closure for the README.

**Exit criteria:**
1. `nix-store -q --tree $(nix-build -A gcc-latest)` → no `/nix/store/*-mes-*` paths.
2. `nix-store -q --tree $(nix-build -A gcc-latest)` → no `/nix/store/*-stdenv-*` paths until the final `gcc-latest` itself.
3. `gcc-latest` compiles a hello-world that runs.

### Phase 9 (stretch) — Cross-arch + reproducibility

- Port codegen to `i686-linux` (smaller register file, different
  ABI).
- Port to `aarch64-linux` (different ISA; 30 % rewrite of codegen).
- Diverse double compile against gcc-built tinycc to attest
  determinism.
- Deterministic builds: hcc must produce byte-identical output for
  identical input. (Easy — no random state.)

## Open questions / risks

1. **Will `precisely_up` actually compile `hcc.hs`?** Our hcc grows
   to maybe 5–10k LoC of Haskell-subset. precisely is fine on its
   own ~2k LoC source. We'll find out at Phase 1; if precisely chokes
   on something (e.g. it has a cap on tuple size, on case-arm count),
   we either work around or patch `precisely.hs` and rebuild.
2. **Will `hcc.c` compile under M2-Planet?** Same risk class. If not,
   we add a small post-processor that simplifies precisely_up's
   output for M2-Planet's tastes (e.g. splitting big initialiser
   arrays, expanding char-cast hex into octets).
3. **tinycc's source uses inline assembly more than I think.** If
   it does, codegen Phase 4 grows by an asm-parser module. ~1 extra
   session.
4. **Float support.** If tinycc-bootstrappable wants doubles for
   anything load-bearing, codegen grows by SSE float ops + a small
   IR float type. ~2 sessions.
5. **Toolchain quirks in M1/hex2.** Section ordering, relocation
   types — Phase 4 will surface these. Worst case we patch
   mescc-tools to add a relocation type we need; mescc-tools is
   in the trust root anyway.

## Effort estimate (honest)

- Phase 0: this session.
- Phases 1–5: 8–14 working sessions.
- Phase 6: 2–3 sessions, but mostly debug.
- Phase 7: open-ended; "iterate on hcc until tinycc compiles"
  could be 5 or 50 sessions depending on how clean tinycc-
  bootstrappable's source already is. live-bootstrap has spent
  years here on the Mes side; we get to skip a lot of that work
  because we're starting from a typed Haskell base.
- Phases 8–9: a session each once 7 lands.

## Order of operations for **this session**

1. Vendor `stage0-posix`, `tinycc/`, `mes/` (for reference, not
   build), `mescc-tools-*`, `utils.nix`, top-level `default.nix`
   from nixpkgs into `vendor/nixpkgs-minimal-bootstrap/`. Sanity-
   check `nix flake show`.
2. Survey tinycc-bootstrappable's C feature use; write
   `phase0-survey.md`.
3. Stand up `vendor/hcc/Main.hs` stub. Write a derivation
   `nix/hcc.nix` that: precisely_up compiles `Main.hs` → `hcc.c`,
   then stdenv cc compiles to a binary (we'll switch to M2-Planet
   in Phase 6).
4. Wire `hcc-stub` into `flake.nix`.
5. Smoke-test: `nix build .#hcc-stub && ./result/bin/hcc-stub`.

That ends Phase 0. Phases 1+ are separate sessions.
