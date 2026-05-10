# HCC-built TinyCC vs MesCC-built TinyCC performance audit

Date: 2026-05-10

## Question

Does the available comparison indicate that we need more efficiency in HCC-generated code?

Short answer: only weakly. The HCC-built final `tcc` is not obviously bloated, and it emits smaller outputs in the small tests here. It is slower than the MesCC-built baseline on a larger TinyCC-source compile workload, but the much larger practical cost is still the HCC/Precisely bootstrap path and HCC-to-M1 generation work needed to produce `tcc` in the first place.

Recommendation: prioritize HCC/Precisely bootstrap path performance first. Treat HCC-generated TinyCC runtime performance as a second-order follow-up, especially for larger compiler workloads, but the evidence here does not show output-size/code-quality collapse in the generated `tcc` binary.

## Targets identified

Relevant HCC-built TinyCC flake targets in this repo:

- `.#tinycc.m2.precisely.m2`: full HCC-built TinyCC using `hcc.m2.precisely.m2`.
- `.#tinycc.m2.precisely.gccm2`: sibling path using `hcc.m2.precisely.gccm2`.
- `.#tinycc.m1.m2.precisely.m2`: M1-artifacts-only variant, useful for isolating HCC-generated M1 artifact production without final TinyCC self-build/install.

Closest MesCC-built baseline found:

- `/home/siraben/nixpkgs`: `pkgs.minimal-bootstrap.tinycc-mes.compiler`
- Baseline compiler path used:
  `/nix/store/5rw53l1mkfaqsk0cgp9dx5qmiini3jnr-tinycc-mes-unstable-2025-12-03`
- Baseline libs path used:
  `/nix/store/rayh0cq2ik1xyw2hclrkdn7c67lppg2r-tinycc-mes-libs-unstable-2025-12-03`

Primary HCC-built compiler path used:

- `/nix/store/5b347w6svmfr56v3z9a748qgxcxy4xqa-tinycc-boot-hcc-m2-precisely-m2-unstable-2024-07-07`

M1-artifacts-only HCC path:

- `/nix/store/pgs6yjfdpfhibyld1d67608557hxw217-tinycc-m1-hcc-m2-precisely-m2-unstable-2024-07-07`

Note: direct flake re-evaluation produced changing derivation hashes for HCC path targets during this audit, apparently because generated source derivations were re-materialized. Therefore the report records output paths from `nix build --print-out-paths --no-link` runs rather than relying on `nix path-info` alone.

## Build-time observations

Commands run:

```sh
command time -p nix build --no-link .#tinycc.m2.precisely.m2
command time -p nix build --print-out-paths --no-link .#tinycc.m2.precisely.m2
command time -p nix build --print-out-paths --no-link .#tinycc.m1.m2.precisely.m2
command time -p nix build --impure --no-link --expr 'let pkgs = import /home/siraben/nixpkgs {}; in pkgs.minimal-bootstrap.tinycc-mes.compiler'
command time -p nix build --impure --no-link --rebuild --expr 'let pkgs = import /home/siraben/nixpkgs {}; in pkgs.minimal-bootstrap.tinycc-mes.compiler'
```

Results:

| Measurement | Result | Notes |
| --- | ---: | --- |
| `.#tinycc.m2.precisely.m2`, first timed realization | 283.39s real | Built `hcc-m2-precisely-m2` and full TinyCC derivation from current store state. |
| `.#tinycc.m2.precisely.m2`, path-resolving realization | 419.68s real | Rebuilt generated HCC sources, HCC, and TinyCC; output path recorded above. |
| `.#tinycc.m1.m2.precisely.m2` | 220.49s real | Built HCC plus M1 artifacts only; no final hex2/link/lib/self-host install path. |
| nixpkgs `minimal-bootstrap.tinycc-mes.compiler` | 0.62s real | Already present/cached; not a cold build. |
| nixpkgs `minimal-bootstrap.tinycc-mes.compiler --rebuild` | 0.73s real | Nix only checked existing output; not useful as a cold MesCC build time. |

Limits: I did not force a cold rebuild of the whole nixpkgs MesCC bootstrap chain. That would be the fairer end-to-end baseline, but it was outside a bounded, non-disruptive audit. The MesCC build-time datapoint above should be read only as "already available in store", not as a MesCC bootstrap timing.

Separation of factors:

- The HCC full TinyCC realization includes generating/building HCC and then running HCC-generated `hcpp`, `hcc1`, and `hcc-m1` to produce TinyCC M1 artifacts, followed by hex2/link and TinyCC self-build stages.
- The M1-artifacts target completed in 220.49s, while the full path completed in 419.68s in a separate run. This suggests a large share of current wall time is in the HCC/HCC-generated frontend-to-M1 path, with substantial additional cost in final linking/lib/self-build stages.
- Nix logs for these derivations were not available via `nix log`, so exact per-step timing inside the TinyCC derivation could not be recovered without another instrumented rebuild.

## Installed binary size and layout

Commands run:

```sh
du -sb \
  /nix/store/5b347w6svmfr56v3z9a748qgxcxy4xqa-tinycc-boot-hcc-m2-precisely-m2-unstable-2024-07-07 \
  /nix/store/5rw53l1mkfaqsk0cgp9dx5qmiini3jnr-tinycc-mes-unstable-2025-12-03 \
  /nix/store/rayh0cq2ik1xyw2hclrkdn7c67lppg2r-tinycc-mes-libs-unstable-2025-12-03

wc -c \
  /nix/store/5b347w6svmfr56v3z9a748qgxcxy4xqa-tinycc-boot-hcc-m2-precisely-m2-unstable-2024-07-07/bin/tcc \
  /nix/store/5rw53l1mkfaqsk0cgp9dx5qmiini3jnr-tinycc-mes-unstable-2025-12-03/bin/tcc

nix develop .#bench -c sh -lc 'size /nix/store/5b347w6svmfr56v3z9a748qgxcxy4xqa-tinycc-boot-hcc-m2-precisely-m2-unstable-2024-07-07/bin/tcc /nix/store/5rw53l1mkfaqsk0cgp9dx5qmiini3jnr-tinycc-mes-unstable-2025-12-03/bin/tcc'
```

Results:

| Item | Size |
| --- | ---: |
| HCC TinyCC store output | 3,617,198 bytes |
| MesCC baseline compiler store output | 970,685 bytes |
| MesCC baseline libs store output | 132,535 bytes |
| HCC final `bin/tcc` | 339,232 bytes |
| HCC `bin/tcc-hcc-stage1` | 2,632,637 bytes |
| HCC `bin/tcc-stage2` | 339,232 bytes |
| MesCC baseline `bin/tcc` | 970,685 bytes |

`size` output:

| Compiler | text | data | bss | dec |
| --- | ---: | ---: | ---: | ---: |
| HCC final `tcc` | 304,952 | 33,048 | 154,568 | 492,568 |
| MesCC baseline `tcc` | 461,740 | 1,240 | 171,168 | 634,148 |

Interpretation: the HCC final `tcc` binary is smaller than the MesCC baseline binary. The HCC store path is larger because it also installs stage1 and stage2 compilers.

## Simple compile and output-size tests

Test input:

```c
#include <stdio.h>
int fib(int n){return n < 2 ? n : fib(n-1) + fib(n-2);}
int main(void){printf("%d\n", fib(10)); return 0;}
```

Commands run used:

```sh
HCC=/nix/store/5b347w6svmfr56v3z9a748qgxcxy4xqa-tinycc-boot-hcc-m2-precisely-m2-unstable-2024-07-07
MES=/nix/store/5rw53l1mkfaqsk0cgp9dx5qmiini3jnr-tinycc-mes-unstable-2025-12-03
MESLIB=/nix/store/rayh0cq2ik1xyw2hclrkdn7c67lppg2r-tinycc-mes-libs-unstable-2025-12-03

$HCC/bin/tcc -B$HCC/lib -o hello-hcc hello.c
$MES/bin/tcc -B$MESLIB/lib -o hello-mes hello.c

$HCC/bin/tcc -B$HCC/lib -c -o hello-hcc.o hello.c
$MES/bin/tcc -B$MESLIB/lib -c -o hello-mes.o hello.c
```

Results:

| Output | Size |
| --- | ---: |
| HCC-linked hello executable | 51,032 bytes |
| MesCC-linked hello executable | 55,532 bytes |
| HCC hello object | 1,132 bytes |
| MesCC hello object | 1,561 bytes |

Both executables printed `55`.

Compile timing loops:

```sh
# 500 object-only compiles, with TMP pointing at the temp dir containing hello.c.
command time -p sh -c 'i=0; while [ $i -lt 500 ]; do /nix/store/5b347w6svmfr56v3z9a748qgxcxy4xqa-tinycc-boot-hcc-m2-precisely-m2-unstable-2024-07-07/bin/tcc -B/nix/store/5b347w6svmfr56v3z9a748qgxcxy4xqa-tinycc-boot-hcc-m2-precisely-m2-unstable-2024-07-07/lib -c -o $TMP/hcc-$i.o $TMP/hello.c; i=$((i+1)); done'
command time -p sh -c 'i=0; while [ $i -lt 500 ]; do /nix/store/5rw53l1mkfaqsk0cgp9dx5qmiini3jnr-tinycc-mes-unstable-2025-12-03/bin/tcc -B/nix/store/rayh0cq2ik1xyw2hclrkdn7c67lppg2r-tinycc-mes-libs-unstable-2025-12-03/lib -c -o $TMP/mes-$i.o $TMP/hello.c; i=$((i+1)); done'

# 200 linked compiles, with TMP pointing at the temp dir containing hello.c.
command time -p sh -c 'i=0; while [ $i -lt 200 ]; do /nix/store/5b347w6svmfr56v3z9a748qgxcxy4xqa-tinycc-boot-hcc-m2-precisely-m2-unstable-2024-07-07/bin/tcc -B/nix/store/5b347w6svmfr56v3z9a748qgxcxy4xqa-tinycc-boot-hcc-m2-precisely-m2-unstable-2024-07-07/lib -o $TMP/hcc-$i $TMP/hello.c; i=$((i+1)); done'
command time -p sh -c 'i=0; while [ $i -lt 200 ]; do /nix/store/5rw53l1mkfaqsk0cgp9dx5qmiini3jnr-tinycc-mes-unstable-2025-12-03/bin/tcc -B/nix/store/rayh0cq2ik1xyw2hclrkdn7c67lppg2r-tinycc-mes-libs-unstable-2025-12-03/lib -o $TMP/mes-$i $TMP/hello.c; i=$((i+1)); done'
```

Results:

| Benchmark | HCC-built `tcc` | MesCC-built `tcc` |
| --- | ---: | ---: |
| 500 object-only compiles | 0.82s real | 1.09s real |
| 200 linked compiles | 0.56s real | 0.60s real |

Interpretation: for tiny inputs, HCC-built `tcc` is at least competitive and was slightly faster in these runs. Output size was also smaller.

## Larger TinyCC-source compile benchmark

To avoid source/header mismatch, I used the exact nixpkgs minimal-bootstrap TinyCC source and generated `tccdefs_` path from the baseline builder:

- Source: `/nix/store/krrasl3572k1g9rimm1pdxpz2mcj8grd-tinycc-unstable-2025-12-03-source/tinycc-cb41cbf`
- `tccdefs`: `/nix/store/04ncxkz5z15x62bspflpfkbplh6dl1am-tccdefs-unstable-2025-12-03`

One direct object compile with warnings enabled:

| Compiler | Time | Object size |
| --- | ---: | ---: |
| HCC-built `tcc` | 0.11s real | 687,668 bytes |
| MesCC-built `tcc` | 0.06s real | 699,522 bytes |

50-iteration object compile loop with `-w`:

```sh
HCC=/nix/store/5b347w6svmfr56v3z9a748qgxcxy4xqa-tinycc-boot-hcc-m2-precisely-m2-unstable-2024-07-07
MES=/nix/store/5rw53l1mkfaqsk0cgp9dx5qmiini3jnr-tinycc-mes-unstable-2025-12-03
MESLIB=/nix/store/rayh0cq2ik1xyw2hclrkdn7c67lppg2r-tinycc-mes-libs-unstable-2025-12-03
SRC=/nix/store/krrasl3572k1g9rimm1pdxpz2mcj8grd-tinycc-unstable-2025-12-03-source/tinycc-cb41cbf
TCCDEFS=/nix/store/04ncxkz5z15x62bspflpfkbplh6dl1am-tccdefs-unstable-2025-12-03
export TMP HCC MES MESLIB SRC TCCDEFS

command time -p sh -c 'i=0; while [ $i -lt 50 ]; do $HCC/bin/tcc -B$HCC/lib -w -c -o $TMP/hcc-$i.o -D BOOTSTRAP=1 -std=c99 -D HAVE_BITFIELD=1 -D HAVE_FLOAT=1 -D HAVE_LONG_LONG=1 -D HAVE_SETJMP=1 -D CONFIG_TCC_PREDEFS=1 -I $TCCDEFS -D CONFIG_TCC_SEMLOCK=0 -I $TMP -I $SRC -D TCC_TARGET_X86_64=1 -D CONFIG_TCCDIR=\"\" -D CONFIG_SYSROOT=\"\" -D CONFIG_TCC_CRTPREFIX=\"{B}\" -D CONFIG_TCC_ELFINTERP=\"\" -D CONFIG_TCC_LIBPATHS=\"{B}\" -D CONFIG_TCC_SYSINCLUDEPATHS=\"/bench/include\" -D TCC_LIBGCC=\"libc.a\" -D TCC_LIBTCC1=\"libtcc1.a\" -D CONFIG_TCCBOOT=1 -D CONFIG_TCC_STATIC=1 -D CONFIG_USE_LIBGCC=1 -D TCC_MES_LIBC=1 -D TCC_VERSION=\"bench\" -D ONE_SOURCE=1 $SRC/tcc.c; i=$((i+1)); done'
command time -p sh -c 'i=0; while [ $i -lt 50 ]; do $MES/bin/tcc -B$MESLIB/lib -w -c -o $TMP/mes-$i.o -D BOOTSTRAP=1 -std=c99 -D HAVE_BITFIELD=1 -D HAVE_FLOAT=1 -D HAVE_LONG_LONG=1 -D HAVE_SETJMP=1 -D CONFIG_TCC_PREDEFS=1 -I $TCCDEFS -D CONFIG_TCC_SEMLOCK=0 -I $TMP -I $SRC -D TCC_TARGET_X86_64=1 -D CONFIG_TCCDIR=\"\" -D CONFIG_SYSROOT=\"\" -D CONFIG_TCC_CRTPREFIX=\"{B}\" -D CONFIG_TCC_ELFINTERP=\"\" -D CONFIG_TCC_LIBPATHS=\"{B}\" -D CONFIG_TCC_SYSINCLUDEPATHS=\"/bench/include\" -D TCC_LIBGCC=\"libc.a\" -D TCC_LIBTCC1=\"libtcc1.a\" -D CONFIG_TCCBOOT=1 -D CONFIG_TCC_STATIC=1 -D CONFIG_USE_LIBGCC=1 -D TCC_MES_LIBC=1 -D TCC_VERSION=\"bench\" -D ONE_SOURCE=1 $SRC/tcc.c; i=$((i+1)); done'
```

Results:

| Benchmark | HCC-built `tcc` | MesCC-built `tcc` |
| --- | ---: | ---: |
| 50 TinyCC-source object compiles | 5.76s real | 3.48s real |
| User CPU | 4.86s | 2.86s |
| Sys CPU | 0.86s | 0.60s |
| First output object size | 687,668 bytes | 699,522 bytes |

Interpretation: on this larger compile workload, the HCC-built `tcc` is about 1.65x slower than the MesCC-built baseline, while producing a slightly smaller object. This is the strongest evidence that HCC-generated `tcc` runtime performance could use attention. It is not evidence of worse emitted object size from `tcc`.

## Generated artifact size signals

For the HCC M1 artifacts target:

```sh
find /nix/store/pgs6yjfdpfhibyld1d67608557hxw217-tinycc-m1-hcc-m2-precisely-m2-unstable-2024-07-07/share/tinycc-hcc-m1 \
  -maxdepth 1 -type f -printf '%f %s\n' | sort
```

Key sizes:

| Artifact | Size |
| --- | ---: |
| `tcc-expanded.c` | 539,319 bytes |
| `tcc.hccir` | 3,577,850 bytes |
| `tcc.M1` | 11,790,615 bytes |
| `tcc-bootstrap-support.M1` | 315,307 bytes |
| `tcc-final-overrides.M1` | 111,543 bytes |

These sizes show a large intermediate/output expansion through HCC IR and M1. That matters for bootstrap time, but the final `tcc` binary is still small.

## Failures and limits

- `nix flake show --all-systems --json` failed because the flake exposes nested non-derivation attrsets under `packages`, leading to `error: expected a derivation`.
- `nix log .#tinycc.m2.precisely.m2` and `nix log .#hcc.m2.precisely.m2` reported no available build log, so precise per-step timings inside derivations were not available.
- A first attempt to compile the repo's `upstream/janneke-tinycc/tcc.c` with the MesCC baseline failed due an `include/stdarg.h` / `__va_arg` mismatch. I replaced that with the exact nixpkgs baseline source and generated `tccdefs` path.
- I did not perform a cold full rebuild of nixpkgs `minimal-bootstrap.tinycc-mes` from Mes/MesCC roots. The baseline build-time result is therefore not comparable to the HCC end-to-end build time.
- There are unrelated pre-existing working tree changes in `hcc_optimization.md` and `nix/hcc-ghc.nix`; I did not edit them.

## Conclusion

The comparison does not primarily point at final HCC-generated TinyCC code size or TinyCC output-code size as the urgent problem. HCC-built final `tcc` is smaller than the MesCC-built baseline, emits smaller objects/executables in the small tests, and is competitive on tiny compile workloads.

There is a real runtime-performance signal on larger inputs: HCC-built `tcc` took 5.76s for 50 TinyCC-source object compiles versus 3.48s for MesCC-built `tcc`. That suggests HCC-generated `tcc` code efficiency is worth investigating, but the magnitude is modest compared with the hundreds of seconds spent in the HCC/Precisely bootstrap and HCC-to-M1 artifact path.

Recommendation: focus first on HCC/Precisely bootstrap path performance: generated HCC source stability, HCC build cost, `hcpp`/`hcc1`/`hcc-m1` throughput, and reducing HCC IR/M1 expansion. After that, profile the HCC-built `tcc` on larger source compiles to recover the roughly 1.6x runtime gap observed here.
