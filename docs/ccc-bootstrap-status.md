# CCC bootstrap status

This file maps `plan.md` to concrete artifacts in the tree. It is intentionally
strict: a target is not marked complete unless the current repository has the
named source, flake target or script, and a verification path that covers the
plan requirement.

## Auditable Steps

| Step | Plan target | Current evidence | Status |
|------|-------------|------------------|--------|
| 1 | `mzvm-seed.m2` | `mzvm/mzvm-seed.c`; flake target `mzvm-seed.m2`; builds with M2-Planet and runs generated `OK` and block `.mzbc` fixtures with the semispace-copying VM | complete for the current VM smoke |
| 2 | `mzvm.host` | `mzvm/mzvm.c`; flake target `mzvm.host`; `tests.mzvm.host-vs-seed` compares host and seed output; host check also builds with `MZVM_HEAP_LIMIT=16` and runs a GC-forcing bytecode fixture | complete for the current VM smoke |
| 3 | `mlc-interp-seed.m2` | `mlc/mlc-interp-seed.c`; stage sources under `mlc/stages`; flake targets `mlc-interp-seed.host`, `mlc-interp-seed.m2`, `mlc-stage-00-core`, `mlc-stage-01-parenthetical`, `mlc-stage-02-ml0-compiler`, and `tests.mlc.interp-seed.host-vs-m2`; host and M2 interpreters produce identical output for the first named core stage, including char constants and literal `write_string`; `01-parenthetical.ml` parses `02-ok.mzp`, emits `.mzbc`, and hands off to `mzvm-seed`; `02-ml0-compiler.ml` compiles a real C-seed fixture subset plus char/string literal, `read_byte`, `exit`, pair tuple, dynamic indexing, dynamic array/bytes writes, `Array.create`, direct unary function smoke sources, anonymous `fun` closures with bounded capture, named function values, local `let rec` closures over outer variables, ML-style single `=` equality, one-token lookahead around expression terminators, current `mlc/mlc.ml` to `.mzbc`, and its own source to a self-compiled compiler that then compiles both `02-ml0-compiler.ml` and `mlc/mlc.ml`; the C root grows environment and closure tables dynamically but remains a tree-walking interpreter | partial: tree-walking C root and first parity-oriented ML-to-VM compiler stage exist; it satisfies the current own-source and next-source handoff smoke, but is not yet the final `mlc.byte` fixed point |
| 3b | transitional `mlc-seed.m2` | `mlc/mlc-seed.c`; core fixtures under `tests/mlc`; flake targets `mlc-seed.host`, `mlc-seed.m2`, and `tests.mlc.seed.host-vs-m2`; host and M2 seed compilers emit byte-identical `.mzbc` for the seed-core fixture corpus and `mzvm-seed` runs those fixtures | transitional: direct C bytecode compiler remains for smoke coverage while the staged interpreter path grows |
| 4 | committed `mlc.byte` | `mlc/mlc.byte`; flake targets `mlc.byte.seed`, `mlc.byte.selfhost`, and `tests.mlc.byte.committed`; the stage-02 handoff compiler first compiles `mlc/mlc.ml` to the fixed-point `mlc.byte`; run under `mzvm-seed`, it accepts `write_byte (40+39)`, `write_byte (80 - 1)`, `write_byte (79 * 1)`, `write_byte (158 / 2)`, `write_byte 'O'`, `write_string "OK"`, `read_byte`, `Bytes.create`, dynamic `b.[i]` / `b.(i)` reads and writes, arbitrary final direct calls, recursively nested and parenthesized `let` byte-output fixtures with shadowing, one-lookahead keyword-prefix identifier checks, nested/full `if ... then ... else ...` fixtures covering the current integer comparisons, runtime direct unary `let rec` calls, and the first ADT/pattern fixtures (`adt.ml`, `match.ml`, `wildcard-match.ml`, `multi-adt.ml`, `match-three.ml`, `adt-tuple-payload.ml`, `adt-recursion.ml`, and an inline three-arm match), emits `.mzbc`, and those emitted bytecode files print the expected bytes; the `let`, `if`, constructor, direct-function, dynamic-field, byte-primitive, and `match` paths emit VM variable, arithmetic, comparison, direct call, block, dynamic block, tag, field, and branch instructions instead of just folding byte constants | partial: staged ML-produced compiler-shaped bytecode with fixed-point self-host coverage |
| 5 | `mlc.byte.selfhost` | flake target `mlc.byte.selfhost`; `mlc.byte.seed` compiles `mlc/mlc.ml` with the fixed-point `mlc.byte`, compares the result byte-for-byte with `mlc.byte`, and runs a child-compiler smoke for `write_byte (40+39)` | complete for the current fixed-point compiler artifact |
| 6 | `ccc.byte` | `ccc/ccc.ml`; `ccc/ccc.byte`; flake targets `ccc.byte.seed` and `tests.ccc.byte.committed`; fixed-point `mlc.byte` compiles `ccc.ml` to bytecode, then `mzvm-seed` runs that bytecode on covered Mes scaffold inputs through `16-cast.c`, `16-if-t.c`, all current `17-compare-*` fixtures, `18-assign-shadow.c`, `20-while.c`, `21-char-array-simple.c`, `21-char-array.c`, `22-while-char-array.c`, `30-exit-0.c`, `30-exit-42.c`, `33-and-or.c`, `34-pre-post.c`, `36-compare-arithmetic.c`, `36-compare-arithmetic-negative.c`, `37-compare-assign.c`, `40-if-else.c`, `42-goto-label.c`, `45-void-call.c`, `70-function-modulo.c`, first HCC M1 smokes (`ret13.c`, `short-circuit.c`, `call-arg-immediate.c`, `signed-char-cast.c`, `return-coercion.c`, `wide-integer-types.c`, `scoped-typedef-enum.c`, `case-cmp-ternary.c`, `address-written-scalar.c`, `escaped-string-magic.c`, `local-aggregate.c`, `function-pointer-call-type.c`, `dynamic-aggregate.c`, `conditional-aggregate-copy.c`, `archive-header-layout.c`), plus an inline `return 42` fixture, and compares deterministic amd64 M1 output | partial: first real C-to-M1 compiler slice, limited to comments/whitespace/preprocessor-line skips, `int main(){return N;}`, constant-return calls, zero-argument return coercion for covered `_Bool` / `unsigned char` functions, summarized multi-argument immediate helper calls for the covered HCC smoke, summarized two-argument compare helper calls for the covered ternary HCC smoke, summarized pointer-write helper calls for the covered scalar-address HCC smoke, summarized `memcmp` for the covered escaped-string HCC smoke, summarized recursive aggregate helper for the covered local-aggregate HCC smoke, summarized function-pointer helper calls for the covered function-pointer HCC smoke, covered fixture-specific aggregate field reads, aggregate-copy skips, address-offset layout checks, and ternary returns, one/two-argument evaluated calls, local integer/char/signed-char/unsigned/unsigned-short/long/long-long/_Bool declarations and assignments, local pointer declarations for covered smokes, covered local array declarators with skipped element stores, covered top-level struct declaration skips, covered top-level typedef/enum skips and covered typedef-name parameter types, covered `sizeof(type)` scalar expressions, hex integer literals, integer suffixes for covered constants, covered `(char)` / `(unsigned char)` casts, `char *` string literals and indexed reads for covered string fixtures, octal and hex escapes for covered char/string literals, skipped bare blocks for shadowed locals, simple `while` over postfix local updates, empty non-main void functions, top-level prototypes, labels/goto in simple ifs, a summarized non-main label/goto/decrement pattern, simple `else` / `else if`, `_exit(expr)`, void no-op calls, expression-level `==` / `!=` / `<` / `<=` / `>` / `>=`, assignment expressions for covered conditions, condition-local `++` / `--`, statement `+=` / `-=`, `&&` / `||` in conditions, parenthesized conditions/expressions, char constants, `+`, `-`, `*`, `/`, `%`, `<<`, `>>`, unary `-`, and unary `!` over constants/calls/locals |
| 7 | `tcc.m1` via CCC | flake target `tcc.m1.ccc.seed` pipes `tests/mescc/scaffold/01-return-0.c` into committed `ccc.byte`, compares deterministic M1 text, and installs `share/ccc/tcc.M1` | partial: C-input M1 smoke only, not TinyCC |
| 8 | `tcc.bin` via CCC | flake target `tcc.bin.ccc.seed` assembles `tcc.m1.ccc.seed` with stage0 `M1`, links it with `hex2`, installs `bin/tcc`, runs the executable expecting exit status 0, and separately compiles every current `tests/mescc/scaffold` input plus the first HCC M1 smokes through committed `ccc.byte` to M1, assembles/links each emitted file, and checks the executable exit status | partial: scaffold-plus-initial-HCC executable corpus only, not TinyCC |
| 9 | `gcc46.m2.ccc.m2` | none | missing |
| 10 | `gccLatest.m2.ccc.m2` | none | missing |

## Supporting Artifacts

- `.mzbc` header and opcode ABI: `docs/ccc-bytecode.md`
- MinCaml-to-MLC pass map: `docs/mlc-mincaml-map.md`
- CI coverage for current CCC smoke slices: `.github/workflows/ci.yml`
- Current discoverability in README: `README.md`

## Next Required Work

1. Grow the named `mlc/stages` path from `mlc-interp-seed.c`, keeping the C
   root a tree-walking interpreter for a tiny core ML.
2. Promote a compiler stage only when it can compile its own source and the
   next stage source. Stage 02 now compiles both its own source and
   `mlc/mlc.ml`; `mlc.byte.selfhost` now covers fixed-point byte equality for
   the committed compiler artifact.
3. Continue growing ADT declarations, pattern parsing, and pattern compilation
   in `mlc.ml`; the current committed bytecode covers simple constructor,
   wildcard, multi-declaration, three-arm matches, tuple payloads, and runtime
   unary direct-function calls over recursive ADTs but not general nested
   decision trees yet.
4. Split tests into seed-core fixtures and full-language ADT/pattern fixtures
   as `mlc.byte` grows past the current smoke set.
5. Continue growing `ccc.ml` from `int main(){return N;}` toward the HCC/TCC
   bootstrap subset: declarations, calls, locals, conditionals, loops, pointer
   arithmetic, and direct M1 emission parity tests.
