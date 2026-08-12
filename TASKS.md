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
  than direct M1 emission, and keep direct-M1 work as a future milestone.
- [x] Make the portable bootstrap's default validation and self-hosting
  limitations explicit, including the aarch64 limitation.

The CCC-specific job intentionally runs the packaged `ccc.asHcc` artifact
through the phase-boundary golden tests. The broader staged, M2-seed, and
OCaml-cross-check suites remain available as repository scripts and should be
run when changing the corresponding stages.
