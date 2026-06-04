# HCC vs M2 M1 Codegen Demos

These files are small inputs for inspecting generated M1 quality from HCC
against the stage0 M2 family.

Use:

```sh
tests/codegen-compare/compare.sh
```

The script writes outputs under `build/codegen-compare/`:

- `*.mesoplanet.M1`: M1 left by `M2-Mesoplanet`'s `M2-Planet` subprocess.
- `*.hcc.hccir`: HCC textual IR from `hcc1`.
- `*.hcc.M1`: M1 emitted by `hcc-m1`.
- `summary.tsv`: line/byte counts for quick comparison.

`M2-Mesoplanet` compiles through a temporary `M2-Planet` M1 file and then runs
`blood-elf`, `M1`, and `hex2`. The script uses `--dirty-mode` and copies that
temporary M1 file for comparison.

`local_aggregate.c` is intentionally HCC-only for this comparison: it uses local
aggregate initialization/copying that this M2 path rejects, which demonstrates
coverage as well as emitted-code quality.
