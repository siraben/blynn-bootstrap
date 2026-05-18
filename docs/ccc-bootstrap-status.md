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
| 4 | committed `mlc.byte` | `mlc/mlc.byte`; flake targets `mlc.byte.seed` and `tests.mlc.byte.committed`; the committed bytecode matches the stage-02 self-compiled ML handoff output for the current `mlc/mlc.ml` lexer/parser/emitter spine; run under `mzvm-seed`, it accepts `write_byte (40+39)`, `write_byte (80 - 1)`, `write_byte (79 * 1)`, `write_byte (158 / 2)`, `write_byte 'O'`, `write_string "OK"`, recursively nested and parenthesized `let` byte-output fixtures with shadowing, one-lookahead keyword-prefix identifier checks, true/false `if ... then ... else ...` fixtures covering the current integer comparisons, and the first ADT/pattern fixtures (`adt.ml`, `match.ml`, `wildcard-match.ml`, `multi-adt.ml`, `match-three.ml`, `adt-tuple-payload.ml`, and an inline three-arm match), emits `.mzbc`, and those emitted bytecode files print the expected bytes; the `let`, `if`, constructor, direct-function, and `match` paths emit VM variable, arithmetic, comparison, block, tag, field, and branch instructions instead of just folding byte constants | partial: staged ML-produced compiler-shaped bytecode with a first ADT/match/direct-function slice, not self-hosted |
| 5 | `mlc.byte.selfhost` | none | missing |
| 6 | `ccc.byte` | `ccc/ccc.ml`; `ccc/ccc.byte`; flake targets `ccc.byte.seed` and `tests.ccc.byte.committed`; current artifact is a seed-compiled smoke bytecode that emits deterministic M1 text under `mzvm-seed` | partial: committed smoke bytecode only |
| 7 | `tcc.m1` via CCC | flake target `tcc.m1.ccc.seed` runs committed `ccc.byte` and installs `share/ccc/tcc.M1` | partial: smoke M1 text only |
| 8 | `tcc.bin` via CCC | flake target `tcc.bin.ccc.seed` assembles `tcc.m1.ccc.seed` with stage0 `M1`, links it with `hex2`, installs `bin/tcc`, and runs the executable expecting exit status 0 | partial: smoke executable only, not TinyCC |
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
   `mlc/mlc.ml`; the final byte-equality self-host check still belongs to
   `mlc.byte`.
3. Continue growing ADT declarations, pattern parsing, and pattern compilation
   in `mlc.ml`; the current committed bytecode covers simple constructor,
   wildcard, multi-declaration, three-arm matches, and non-recursive unary
   direct-function calls but not recursive/nested decision trees yet.
4. Split tests into seed-core fixtures and full-language ADT/pattern fixtures
   as `mlc.byte` grows past the current smoke set.
5. Add the `mlc.byte.selfhost` byte-equality target once `mlc.byte` can compile
   the full `mlc.ml` source to the same bytecode artifact.
