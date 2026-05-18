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
| 3 | `mlc-seed.m2` | `mlc/mlc-seed.c`; `tests/mlc/*.ml`; flake targets `mlc-seed.host`, `mlc-seed.m2`, and `tests.mlc.seed.host-vs-m2`; host and M2 seed compilers emit byte-identical `.mzbc` for the fixture corpus and `mzvm-seed` runs all fixtures | partial: small expression compiler, local bindings, and narrow ADT match |
| 4 | committed `mlc.byte` | `mlc/mlc.byte`; flake targets `mlc.byte.seed` and `tests.mlc.byte.committed`; the committed bytecode matches M2-seed output for the current placeholder `mlc/mlc.ml` and runs under `mzvm-seed` | partial: committed smoke bytecode only |
| 5 | `mlc.byte.selfhost` | none | missing |
| 6 | `ccc.byte` | `ccc/ccc.ml`; `ccc/ccc.byte`; flake targets `ccc.byte.seed` and `tests.ccc.byte.committed`; current artifact is a seed-compiled smoke bytecode that runs under `mzvm-seed` | partial: committed smoke bytecode only |
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
