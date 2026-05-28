# MLC idiom audit

This audit tracks places where `mlc/mlc.ml` is still written in a seed-flavored
style even though the pipeline is now strong enough to use a more idiomatic ML
surface. The rule for cleanup is staged: before `mlc.ml` depends on a nicer
construct, the immediately previous compiler in the bootstrap path must compile
that construct and have a check for it.

## Current evidence

- `mlc/stages/02-ml0-compiler.ml` already compiles ordinary char literals.
  Its own parser uses char literals for whitespace, delimiters, keyword heads,
  and MZBC syntax, and `nix/mlc-stage-02-ml0-compiler.nix` checks
  `write_byte 'O'`.
- Decimal escaped char literals such as `'\013'` are now covered on both sides
  of the handoff: stage 02 compiles them, and the `mlc.ml` parser accepts them
  in code compiled by the generated compiler.
- Stage 02 also compiles string literals, `String.length`, `Bytes.create`,
  dynamic string/bytes indexing, closures, and the early `expect_string`
  primitive. Those are enough to support string-based keyword helpers in
  `mlc.ml`.
- Stage 03 has the cleaner parse helper shape: `p_try_string`,
  `p_keyword_at`, `p_need_string`, `p_need_keyword`, explicit parse replies,
  and HCC-style precedence climbing. It is not yet strong enough to compile
  `mlc.ml`, so those helpers are a model, not the active bootstrap producer.
- `mlc.ml` now has the stage-02-compatible core of that parser layer:
  tuple-encoded `p_ok` / `p_err` replies, `p_force`, `p_try_char`,
  `p_try_string`, `p_try_keyword`, `p_try_ident`, and corresponding `p_need_*`
  helpers, tuple-position optional helpers (`p_optional_pos`,
  `p_optional_char_pos`, `p_optional_string_pos`), plus first-order bind
  helpers such as `p_bind_char_keep` and `bind_expect_char_keep` for common
  delimiter continuations. This keeps the parser state explicit while avoiding
  a dependency on ADT syntax before stage 02 can compile ADTs in the compiler
  implementation.
- A scan of `mlc/mlc.ml` after the char-literal cleanup found no remaining
  direct `src.[...] == N` ASCII source-character checks; the remaining
  numeric byte writes are VM bytecode opcodes or data bytes rather than parser
  delimiters.

## Rewrite now

These can move directly into `mlc.ml` because stage 02 already compiles them:

- Replace ASCII source-character constants with char literals:
  `39` -> `'\''`, `34` -> `'"'`, `40` -> `'('`, `41` -> `')'`,
  `44` -> `','`, `45` -> `'-'`, `46` -> `'.'`, `58` -> `':'`,
  `59` -> `';'`, `60` -> `'<'`, `61` -> `'='`, `62` -> `'>'`,
  `91` -> `'['`, `93` -> `']'`, `95` -> `'_'`, `123` -> `'{'`,
  `124` -> `'|'`, and `125` -> `'}'`.
- Replace character-class ranges with char ranges:
  digits, uppercase letters, lowercase letters, and `_`.
- Replace byte-emission magic for the MZBC header with char literals:
  `write_byte 'M'; write_byte 'Z'; write_byte 'B'; write_byte 'C'`.
- Continue moving delimiter and keyword parsing through `p_try_*` / `p_need_*`
  instead of hand-written nested checks.

## Rewritten

- `mlc.ml` now uses ordinary char literals for the MZBC header,
  character-class ranges, digit arithmetic, whitespace checks, ADT/type
  delimiters, pattern payload delimiters, operator tokens, string/debug format
  delimiters, dynamic indexing delimiters, and match-case bars.
- Hand-spelled keyword recognizers like `is_write_byte_at` and
  `is_debug_printf_at` now route through shared `string_at` / `keyword_at`
  helpers. Stage 02 already supports the required string literals, string
  length, and indexing.
- `mlc.ml` now has `need_string` / `need_keyword`, and uses them for the
  fixed `with` / `->` match syntax, direct `write_byte`, top-level
  `write_string`, debug/exit/read primitives, dotted `String.length` /
  `Bytes.*`, and `Cell.*` advances.
- Stage 03 now splits optional parser replies into a real `PosSome` /
  `PosNone` option layer plus `p_option_pos` / `p_optional_pos` state
  projection. This is the ADT-backed Parsec-style shape that `mlc.ml` should
  inherit once ADTs are promoted into its previous producer.
- Raw local `exit 1` parse failures in `mlc.ml` are centralized through
  `parse_fail`, and the char literal, identifier, keyword/lookahead,
  record/type declaration delimiter paths, record literal delimiters, pattern
  payload delimiters, expression-level and top-level `let` delimiters,
  optional top-level `in`, `if`/`then`/`else`, debug/write string openers,
  tuple argument delimiters, and dynamic indexing delimiters now use the
  tuple-encoded parse reply helpers.
- Character literal closing delimiters now use `p_bind_char_keep`, the
  stage-02-compatible first-order spelling of the parser-bind pattern used more
  generally in CCC and the later stage-03 parser.
- Parenthesized expression and dynamic index delimiters now use
  `bind_expect_char_keep`, avoiding repeated unpack/expect/repack code while
  preserving the tuple-encoded parser reply surface.
- Optional record delimiters, match-case bars, tuple commas, and dynamic store
  arrows now use `p_optional_char_pos` / `p_optional_string_pos` instead of
  manually unpacking `p_optional` replies.
- Optional top-level `in` probes now go through `p_optional_end_pos`, and the
  record field parser uses `p_need_char` for the required closing `}` instead
  of open-coding a try/force path.

## Promote before use

These need a stronger previous stage before they should become required by
`mlc.ml`:

- General ADT and pattern matching inside the compiler implementation. Stage 02
  cannot compile those; keep them in `mlc.byte` and successor stages until the
  promoted predecessor can compile them.
- Record-heavy internal compiler data structures. Stage 02 does not compile
  records, so `mlc.ml` can accept records in user programs but should not depend
  on records internally until the previous compiler stage does.
- ADT-backed Parsec-style parser replies in `mlc.ml`. Stage 02 supports the
  tuple-encoded `p_ok` / `p_err` layer now used by `mlc.ml`, but proper
  `ParseOk` / `ParseErr` constructors in the compiler implementation require
  promoting ADTs into the previous stage first. The target option-state shape
  now lives in stage 03 as `PosSome` / `PosNone`; keep the fixed-point compiler
  on tuple-encoded options until its producer can compile those constructors.
- Higher-order parser `bind` in `mlc.ml`. Stage 02 can compile closures, but
  the current fixed-point `mlc.ml` compiler cannot compile dynamic function
  application in its own source yet; keep the active parser layer first-order
  until that self-hosting gap is closed.
- Full ML type inference in the active compiler. Stage 03 has a small static
  checker, not Hindley-Milner inference, and is not yet self-compiling.

## Suggested order

1. Convert `mlc.ml` ASCII constants to ordinary char literals. This is
   done for the parser core, header helpers, type/pattern parsing, operator
   parsing, string/debug parsing, and dynamic indexing paths.
2. Add `string_at` and `keyword_at` to `mlc.ml`, then collapse the `is_*_at`
   functions to data-like spellings. This is done for the shared recognizer
   layer.
3. Add `need_string` / `need_keyword` to `mlc.ml` and replace `expect_with`,
   `expect_arrow`, and fixed primitive spelling code. This is done for the
   current primitive/module-name advances.
4. Keep moving `mlc.ml` parser branches from nested delimiter checks to
   `p_try_*` / `p_need_*`, with `parse_fail` as the only raw process-exit
   boundary. Stage 03 now has the target `PosSome` / `PosNone` option-state
   shape; the fixed-point compiler should adopt it after the predecessor can
   compile ADTs in its own source.
5. Promote ADTs into the previous stage, then replace the tuple-encoded parser
   replies with proper `ParseOk` / `ParseErr` constructors.
