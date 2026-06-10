# M2-Planet: accepted subset and codegen cost model

Working notes for the two seed programs (`ccc/vm/mzvm.c`,
`ccc/seed/mlc-interp-seed.c`), distilled from making them M2-Planet-clean
and from hand-tuning the VM's hot paths. Numbers were measured on the
amd64 backend of mescc-tools 1.9.1; the benchmark is the M2-built VM
running ccc1 over all of preprocessed TinyCC (737 KB of C).

## Subset rules (what M2-Planet accepts, beyond the obvious)

- `&&` and `||` are **bitwise and never short-circuit** (`2 && 4 == 0`).
  Only chains of 0/1-valued comparisons behave as expected; guards that
  protect a dereference (`p != NULL && p->x`) must be nested ifs.
- Pointer arithmetic `p + i` / `&p[i]` is **unscaled**; subscripts `p[i]`
  scale correctly (including negative constant indices and struct-member
  bases). `char **` works; `T **` for struct `T` is rejected outright.
- Subscripting a function-call result scales by 8 regardless of type;
  a cast adjacent to a subscript or `->` rebinds: `(size_t)a->b` parses
  as `((size_t)a)->b`, and `(word)(unsigned char)bp[i]` rescales `i`.
  Load into a plain local first, then mask/cast.
- Integer literals wider than 32 bits are rejected ("unsupported size 64
  when storing number in register"); split into arithmetic on smaller
  literals.
- `continue` inside `switch` is rejected ("Not inside of a loop").
- Local arrays miscompile when they decay to pointer arguments; direct
  indexing of local arrays is fine.
- M2libc: no `atol` (only `atoi`); `EOF` is `0xFFFFFFFF` (only compare
  with `==`); `calloc` zeroes byte-at-a-time (avoid for large regions —
  use `malloc` when every word is written before being read).

## Cost model (measured)

M2-Planet does no register allocation and no inlining. Probe functions
compiled to these instruction counts:

| pattern | insns |
|---|---|
| `return (n << 1) \| 1;` as a function body | 13 |
| the same expression inlined at the call site | ~13 |
| call overhead per call site (frame save/restore, arg push, ret) | ~8–10 |
| `garr[g1 + 1] + garr[g1 + 1]` (recomputed) | 32 |
| hoisting that subexpression into a local | 30 |

Consequences:

- Every operator costs a fixed push/pop ceremony (~3–5 insns); every
  variable access (local or global alike) is a memory load (~2 insns).
  Hoisting common subexpressions into locals barely pays (30 vs 32);
  reducing the *number of operations* is what matters.
- A call to a tiny helper costs roughly the body again in frame
  ceremony. Helpers like `mkint`/`untag`/`pop` in per-instruction paths
  double or triple the work; inline them in hot paths, keep them for
  cold paths and readability.
- Tagged-value identities avoid untag/retag round-trips entirely:
  `mkint(untag(a) + untag(b))` = `a + b - 1`,
  `mkint(untag(a) - untag(b))` = `a - b + 1`, and signed comparisons can
  be done directly on tagged values (for odd x=2a+1, y=2b+1:
  x < y iff a < b). Unsigned comparisons must still untag (the tag shift
  drops the top bit).

## switch lowering (the big one)

`switch` compiles to a **linear comparison chain executed in REVERSE
source order** — the last `case` in the source is the first compared at
run time (~3 insns per case tried, then a `jmp` per dispatch):

```
:_SWITCH_TABLE_f_0
mov_rax, %9         # last source case, compared first
cmp_rbx,rax
je %_SWITCH_CASE_9_f_0
mov_rax, %2
...
```

For a 50-case interpreter dispatch this is ~75 insns per instruction if
cases sit in numeric order. Ordering the cases **coldest-first /
hottest-last** dropped the dispatch from 31% to 9% of total VM time
(perf on the M2 binary; blood-elf symbols make `perf` usable directly).

## Measured impact on the VM (ccc1 compiling TinyCC)

| change | M2-built mzvm | gcc -O2 mzvm |
|---|---|---|
| baseline (post escape-decode fix) | 35.0s | 6.2s |
| case reorder, hot-first (wrong way!) | 33.6s | — |
| + inline hot bodies, tagged identities, sentinel STOP (no per-dispatch pc check) | 31.7s | 4.9s |
| + case reorder hot-LAST (chain is reversed) | 19.9s | 4.7s |

The remaining profile is flat: ~22% in the fetch/loop head (irreducible
global loads under this codegen), ~9% dispatch chain, the rest spread
over case bodies and the GC. Further wins come from rebuilding the VM
with the freshly bootstrapped TCC rather than from more C tuning.
