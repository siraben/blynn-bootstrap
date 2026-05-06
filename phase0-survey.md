# Phase 0 Survey

This repo now vendors the local nixpkgs minimal-bootstrap definitions used as
the replacement target:

- `vendor/nixpkgs-minimal-bootstrap/stage0-posix/`
- `vendor/nixpkgs-minimal-bootstrap/tinycc/`

The MesCC replacement edge is the first compiler in
`tinycc/bootstrappable.nix`:

```sh
mes --no-auto-compile -e main mescc.scm -- -S -o tcc.s ... tcc.c
mes --no-auto-compile -e main mescc.scm -- -L ... -l c+tcc -o tcc tcc.s
```

The current GHC-backed bridge replaces that edge with:

```sh
hcc -o tcc ... -D ONE_SOURCE=1 tcc.c
```

For now `hcc` uses a temporary `cc` backend after the hcc driver boundary.
That keeps the bootstrap call site independent of Mes while native M1 codegen
is implemented behind the same command line.

## Source Revisions

- tinycc-bootstrappable revision:
  `ea3900f6d5e71776c5cfabcabee317652e3a19ee`
- tinycc-mes revision:
  `cb41cbfe717e4c00d7bb70035cda5ee5f0ff9341`

## Current hcc Frontend Coverage

Already implemented and tested with GHC:

- C tokenization for identifiers, integer literals, character literals, string
  literals, comments, directives, and common punctuators/operators.
- Object-like `#define`, `#undef`, inactive-branch removal for `#if`,
  `#ifdef`, `#ifndef`, `#elif`, `#else`, and `#endif`.
- Temporary no-op `#include` handling for parser bring-up.
- Parsing for:
  - global variables
  - function definitions
  - `void`, `int`, `char`, `unsigned`, `long`, named builtin typedefs
  - pointer and array declarators
  - local declarations
  - `return`, `if`, `while`, `do while`, `for`, blocks
  - calls, indexing, assignment, unary ops, and binary precedence

Current parser smoke:

- `vendor/blynn-compiler/pack_blobs.c`
- `vendor/blynn-compiler/vm.c`

Current tinycc bridge smoke:

- `nix build .#tinycc-boot-hcc`
- `./tcc -version`
- `./tcc -c smoke.c -o smoke.o`

## Known Gaps Before Native hcc Can Compile tinycc Itself

Preprocessor:

- Real include search and include guards.
- Function-like macros.
- Macro stringification and token pasting.
- Constant-expression evaluation beyond the current simple `0`, `1`,
  `defined`, and object-macro truthiness cases.

Parser:

- `typedef` tracking.
- `struct`, `union`, `enum`, and bitfields.
- Storage classes and qualifiers as typed metadata instead of skipped words.
- K&R-style declarations if the target corpus requires them.
- Initializer lists and designated initializers.
- `switch`, `case`, `default`, `break`, `continue`, and `goto`.
- Ternary and comma expressions.
- Casts, `sizeof(type)`, compound assignment, pre/post inc/dec.
- Function pointers and full declarator nesting.
- GNU attributes and selected builtins.

Lowering/codegen:

- Type layout and integer promotions.
- IR generation.
- M1 x86_64 emission.
- Linkage with stage0-posix `M1`, `hex2`, and `blood-elf`.

## Replacement State

The repository now has a working Mes-free development replacement for the first
tinycc compiler edge:

- `packages.hcc-ghc`: GHC-built hcc driver.
- `packages.tinycc-boot-hcc`: tinycc boot compiler built by invoking `hcc`.

This is not yet the final seed-trust story because the hcc backend delegates to
host `cc`. The next step is to replace that backend with M1 emission while
keeping `packages.tinycc-boot-hcc` as the integration target.
