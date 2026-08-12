# PR #68 follow-up tasks

Tracked follow-ups for the CCC bootstrap review. The target and parity items
are required for the CCC path to be considered merge-ready; the remaining
items document compatibility and scope explicitly.

- [x] Propagate `hcc1 --target` through the wrappers and CCC driver.
- [x] Emit the canonical HCCIR `T <target>` line and test target-sensitive
  word sizes.
- [x] Make CCC-specific golden and target checks required in GitHub Actions.
- [x] Preserve the existing `gnuHello` flake outputs while adding CCC.
- [x] Document that PR #68 currently uses the legacy `hcc-m1` backend rather
  than direct M1 emission.
- [x] Make the portable bootstrap's default validation and self-hosting
  limitations explicit, including the aarch64 limitation.

Open follow-up milestones:

- [ ] Replace the HCCIR-plus-`hcc-m1` implementation with the planned direct
  M1 backend.
- [ ] Add full fixture, host-OCaml, and M2-seed parity suites as required CI
  jobs. The current required CCC job covers phase-boundary golden tests and
  all supported target plumbing; `ccc.asHcc` itself still runs the staged
  fixpoints and M2 seed build.
- [ ] Enable and verify the portable tcc self-host fixpoint on aarch64.
- [ ] Add a reproducible end-to-end CCC-vs-Blynn/HCC benchmark job rather than
  relying only on the documented one-off timing table.

The CCC-specific job intentionally runs the packaged `ccc.asHcc` artifact
through the phase-boundary golden tests and target checks. The broader staged,
M2-seed, and OCaml-cross-check suites remain available as repository scripts
and should be run when changing the corresponding stages.
