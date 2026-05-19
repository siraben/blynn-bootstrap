# MLC idiom audit

This audit tracks places where `mlc/mlc.ml` is still written in a seed-flavored
style even though the pipeline is now strong enough to use a more idiomatic ML
surface. The rule for cleanup is staged: before `mlc.ml` depends on a nicer
construct, the immediately previous compiler in the bootstrap path must compile
that construct and have a check for it.

## Current evidence

- `mlc/stages/02-ml0-compiler.ml` already compiles raw and escaped char
  literals. Its own parser uses char literals for whitespace, delimiters,
  keyword heads, and MZBC syntax, and `nix/mlc-stage-02-ml0-compiler.nix`
  checks `write_byte 'O'`.
- Stage 02 also compiles string literals, `String.length`, `Bytes.create`,
  dynamic string/bytes indexing, closures, and the early `expect_string`
  primitive. Those are enough to support string-based keyword helpers in
  `mlc.ml`.
- Stage 03 has the cleaner parse helper shape: `p_try_string`,
  `p_keyword_at`, `p_need_string`, `p_need_keyword`, explicit parse replies,
  and HCC-style precedence climbing. It is not yet strong enough to compile
  `mlc.ml`, so those helpers are a model, not the active bootstrap producer.
- A scan of `mlc/mlc.ml` after `b49f06f` found roughly 320 numeric character
  comparisons or byte writes, including about 216 direct `src.[...] == N`
  source-character checks. Most are now avoidable.

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
- Replace hand-spelled keyword recognizers like `is_write_byte_at` and
  `is_debug_printf_at` with a shared `string_at` / `keyword_at` helper.
  Stage 02 already supports string literals, string length, and indexing.
- Use `expect_string`-style helpers in `mlc.ml` for fixed spellings such as
  `with`, `->`, primitive names, and dotted module names.

## Promote before use

These need a stronger previous stage before they should become required by
`mlc.ml`:

- General ADT and pattern matching inside the compiler implementation. Stage 02
  cannot compile those; keep them in `mlc.byte` and successor stages until the
  promoted predecessor can compile them.
- Record-heavy internal compiler data structures. Stage 02 does not compile
  records, so `mlc.ml` can accept records in user programs but should not depend
  on records internally until the previous compiler stage does.
- Broad Parsec-style parser combinators in `mlc.ml`. Stage 02 supports
  closures and `p_bind`, but a wholesale parser rewrite should first be covered
  by a previous-stage fixture that compiles nested binds, `try`/`need` helpers,
  and failure propagation in the exact style used by the compiler.
- Full ML type inference in the active compiler. Stage 03 has a small static
  checker, not Hindley-Milner inference, and is not yet self-compiling.

## Suggested order

1. Convert `mlc.ml` ASCII constants to char literals. This is low-risk,
   mechanical, and stage02-covered.
2. Add `string_at` and `keyword_at` to `mlc.ml`, then collapse the `is_*_at`
   functions to data-like spellings.
3. Add `need_string` / `need_keyword` to `mlc.ml` and replace `expect_with`,
   `expect_arrow`, and fixed primitive spelling code.
4. Add previous-stage tests for the exact parser-combinator style needed by
   the next `mlc.ml` parser cleanup.
5. Only after the previous stage can compile those helpers, move the larger
   `mlc.ml` parser toward the stage03/HCC `ParseLite` shape.
