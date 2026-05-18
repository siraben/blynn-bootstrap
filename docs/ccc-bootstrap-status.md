# CCC bootstrap status

This file maps `plan.md` to concrete artifacts in the tree. It is intentionally
strict: a target is not marked complete unless the current repository has the
named source, flake target or script, and a verification path that covers the
plan requirement.

## Auditable Steps

| Step | Plan target | Current evidence | Status |
|------|-------------|------------------|--------|
| 1 | `mzvm-seed.m2` | `mzvm/mzvm-seed.c`; flake target `mzvm-seed.m2`; builds with M2-Planet and runs the generated `OK` `.mzbc` fixture | complete for the first VM smoke |
| 2 | `mzvm.host` | `mzvm/mzvm.c`; flake target `mzvm.host`; `tests.mzvm.host-vs-seed` compares host and seed output | complete for the first VM smoke |
| 3 | `mlc-seed.m2` | `mlc/mlc-seed.c`; `tests/mlc/ok.ml`; `tests/mlc/arithmetic.ml`; flake target `mlc-seed.m2`; M2-built compiler emits `.mzbc` and `mzvm-seed` runs both fixtures | partial: small expression compiler only |
| 4 | committed `mlc.byte` | none | missing |
| 5 | `mlc.byte.selfhost` | none | missing |
| 6 | `ccc.byte` | none | missing |
| 7 | `tcc.m1` via CCC | none | missing |
| 8 | `tcc.bin` via CCC | none | missing |
| 9 | `gcc46.m2.ccc.m2` | none | missing |
| 10 | `gccLatest.m2.ccc.m2` | none | missing |

## Supporting Artifacts

- `.mzbc` header and opcode ABI: `docs/ccc-bytecode.md`
- MinCaml-to-MLC pass map: `docs/mlc-mincaml-map.md`
- CI coverage for current CCC smoke slices: `.github/workflows/ci.yml`
- Current discoverability in README: `README.md`

## Next Required Work

1. Replace the placeholder `mlc/mlc.ml` with a real MinCaml-shaped compiler
   spine: lexer, parser, AST, ADT/pattern nodes, and bytecode emitter for a
   small expression subset.
2. Grow `mlc-seed.c` from the current `write_byte` fixture compiler into a
   mechanical seed compiler for that same subset.
3. Add golden `.ml` fixtures that compare `mlc-seed` bytecode with host-built
   expectations before committing any `mlc.byte` artifact.
4. Only after `mlc-seed` can compile `mlc.ml`, commit `mlc.byte` and add the
   self-host byte equality target.
