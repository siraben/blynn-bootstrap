# PR #68 follow-up tasks

This ledger records implementation status. Design rationale belongs in
[`ccc/stages/README.md`](ccc/stages/README.md); stage-specific rules belong in `ccc/docs/`.

## Completed

- [x] Propagate `hcc1 --target` through the wrappers and CCC driver.
- [x] Emit the canonical HCCIR `T <target>` line and test target-sensitive
  word sizes.
- [x] Add the CCC golden and target checks to pull-request CI.
- [x] Preserve the existing `gnuHello` flake outputs while adding CCC.
- [x] Document that CCC currently uses the legacy `hcc-m1` backend.
- [x] Document portable-bootstrap validation and self-hosting limits,
  including the aarch64 limitation.

## Open milestones

- [ ] Replace textual HCCIR plus `hcc-m1` with a direct M1 backend.
- [ ] Promote the full fixture, host-OCaml, and M2-seed parity suites to
  required CI jobs where their runtime permits.
- [ ] Enable and verify the portable TinyCC self-host fixpoint on aarch64.
- [ ] Add a reproducible end-to-end CCC-versus-Blynn/HCC benchmark job.

The `tests.ccc.golden` CI job runs the packaged `ccc.asHcc` artifact
through phase-boundary golden tests and target checks. The broader staged,
M2-seed, and host-OCaml suites remain available as repository scripts and
should be run when changing the corresponding stages.
