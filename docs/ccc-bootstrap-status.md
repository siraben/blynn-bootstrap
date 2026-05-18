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
| 3 | `mlc-seed.m2` | `mlc/mlc-seed.c`; core fixtures under `tests/mlc`; flake targets `mlc-seed.host`, `mlc-seed.m2`, and `tests.mlc.seed.host-vs-m2`; host and M2 seed compilers emit byte-identical `.mzbc` for the seed-core fixture corpus and `mzvm-seed` runs those fixtures | partial: seed now targets the small core; ADT declarations and pattern matching are intentionally left for `mlc.ml` |
| 4 | committed `mlc.byte` | `mlc/mlc.byte`; flake targets `mlc.byte.seed` and `tests.mlc.byte.committed`; the committed bytecode matches M2-seed output for the current core-language `mlc/mlc.ml` lexer/parser/emitter spine, which runs under `mzvm-seed` | partial: tiny compiler-shaped bytecode only, not self-hosted |
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

1. Keep `mlc-seed.c` to a tiny core ML: variables, literals, lambdas or direct
   functions, application, conditionals, `let`, tuples, arrays/bytes, and I/O.
2. Move ADT declarations, pattern parsing, and pattern compilation into
   `mlc.ml` instead of strengthening the C seed further.
3. Split tests into seed-core fixtures and, once `mlc.byte` can compile them,
   full-language ADT/pattern fixtures.
4. Only after the core seed can compile `mlc.ml`, commit `mlc.byte` and add the
   self-host byte equality target.
