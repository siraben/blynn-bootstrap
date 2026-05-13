# Tests

The test tree is intentionally small. HCC is a bootstrap compiler, so the main
gates are: can the compiler build, can its M1 output execute, does its MesCC
compatibility corpus still pass, and do independent build paths produce the
same TinyCC M1 artifacts.

| Path | Purpose | Main flake attributes |
| --- | --- | --- |
| `tests/hcc/pp-smoke.c` | Preprocessor sanity input used while building every HCC binary. | Built inside `.#hcc.*` |
| `tests/hcc/parse-smoke.c` | Parser/checker sanity input used while building every HCC binary. | Built inside `.#hcc.*` |
| `tests/hcc/scalar-immediate-smoke.c` | Checks scalar immediate lowering and generated IR in the HCC build derivation. | Built inside `.#hcc.*` |
| `tests/hcc/diagnostics/` | Negative compile tests for errors that should remain hard failures. | Built inside `.#hcc.*` |
| `tests/hcc/m1-smoke/` | Executable smoke programs compiled by HCC to HCCIR, lowered by `hcc-m1`, assembled by stage0 `M1`/`hex2`, and run. | `.#tests.smoke.m1`, `.#tests.smoke.m1-i386`, `.#tests.smoke.m1-aarch64`, `.#tests.host.ghc.native.smoke.m1`, `.#tests.host.ghc.native.smoke.m1-i386`, `.#tests.host.ghc.native.smoke.m1-aarch64` |
| `tests/hcc/precisely-dialect/` | Tiny Blynn-Haskell dialect fixtures for syntax HCC relies on. | `.#tests.precisely.dialect` |
| `tests/mescc/scaffold/` | MesCC scaffold cases used as an executable C subset compatibility check. | `.#tests.mescc`, `.#tests.host.ghc.native.mescc` |

The broader bootstrap gates live outside `tests/`:

| Attribute | Purpose |
| --- | --- |
| `.#tests.tinyccM1.native-vs-faithful` | Builds TinyCC M1 artifacts through native and faithful HCC paths and byte-compares the expected-identical final M1 files. |
| `.#tinycc.*` | Builds the HCC-produced TinyCC bootstrap compiler and its self-hosted successors. |
| `.#bootstrap.*` | Drops the HCC-built TinyCC into the nixpkgs minimal-bootstrap graph. |
