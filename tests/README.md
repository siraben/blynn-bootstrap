# Tests

The Nix-facing gates are intentionally small. `tests/hcc/pp-smoke.c` and
`tests/hcc/parse-smoke.c` are the compile-time sanity inputs used while
building HCC itself. `tests/hcc/m1-smoke` contains the executable M1 backend
smokes run by `.#tests.smoke.m1` and `.#tests.smoke.m1-i386`.
`tests/hcc/precisely-dialect` checks the
small set of Blynn Haskell syntax features that HCC relies on, and
`tests/hcc/mutable-io` proves the mutable IO primitive path. The
`tests/mescc/scaffold` directory keeps only the MesCC scaffold cases currently
run by `.#tests.mescc`; broader TinyCC self-hosting is covered by the
`tinycc.*` flake targets.
