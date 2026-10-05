# Host-built M2 grammar experiment

```sh
nix build .#m2.planet.grammar-gcc-debug
nix build .#checks.x86_64-linux.m2-grammar-debug
nix build .#hcc.ghc.precisely.grammar-gcc-debug
nix build .#tests.grammar-debug.sources .#tests.grammar-debug.golden \
  .#tests.grammar-debug.cpu .#tests.grammar-debug.tinycc-parity
nix build .#tinycc.ghc.precisely.grammar-gcc-debug
bash tests/m2-grammar/provenance.sh
```

The debug compiler uses host GCC, the content-hashed grammar fork at
`ad19a2d9954f5861b9f55b0306e5c4577100ddfa`, three isolated lowering/include
patches, its pinned M2libc, and stage0's `blood-elf`, `M1`, and `hex2`.
The adapter accepts repeated `-f`/`--file`, one `-o`/`--output`, `-I`, `-D`,
`--architecture` (`amd64` or `x86_64`), and `--operating-system Linux`.
Long file/output/architecture/OS options also accept `=value`.
It does not silently include a working-directory `bootstrappable.c`.

The check executes a local semantics fixture and 19 pinned upstream programs
with both the fork and GCC, requiring successful exit and identical stdout.
The local fixture also requires literal `OK` output. It covers global/static
postfix lvalues, array decay, pointer arithmetic/differences, short-circuiting,
conditional/comma expressions, loop declarations, and allocation. Upstream
coverage includes indirect calls, casts, and subscripts. One additional
upstream comma fixture uses a non-ISO-C conditional-expression extension; it
is run for successful exit separately, not claimed as GCC parity.

Wrapper tests exercise spaces, multiple files, both option spellings,
include/define forwarding, an empty PATH, malformed/unsupported options,
compiler-error propagation, destination preservation, and temporary cleanup.
The provenance script queries recursive **derivation inputs**, not merely
runtime references, and fails if either host-built M2 or the fork source
enters default Blynn, faithful HCC, or faithful TinyCC. It also requires the
new HCC variant to depend on the isolated generator and fork, but not faithful
crossly-generated C. CI runs this audit and the grammar/HCC checks without
replacing existing bootstrap checks.

## HCC source/RTS transition

`hcc.ghc.precisely.grammar-gcc-debug` uses host GHC to build an isolated Precisely
generator. Unlike the faithful crossly RTS, its `RTSPrecisely.hs` addresses
memory through explicit `char*` byte offsets, valid under the fork's scaled
pointer arithmetic. A debug-only source patch adds `m2-grammar-debug` mode:
it defaults to `TOP=134217728` and enables the external allocator/range-checked
RTS. `m2-grammar-debug top WORDS` also accepts the shared source-level TOP API
(canonical decimal 1024..536870912), so the C-generation stage can select
HCPP/HCC1 heaps independently. Invalid/missing/extra TOP arguments exit nonzero
with the same flushed diagnostic as the original GHC generator.
Both settings are emitted by the generator, not substituted into generated C.
The fork compiles that C with `hcc_runtime_m2.c`, and also builds `hcc-m1`.
The default GHC generator, faithful source patches, and portable stages remain
unchanged. The old `gccm2` targets still mean the original GCC-built Mesoplanet.

Source-contract tests compare the published C with the original generated
bytes, exercise the new mode, and compare default-mode C byte-for-byte with
the unmodified GHC generator, including explicit TOP values. Rejection tests
exercise the GHC `System.Exit` shim. HCC's compiler smoke and golden tests run with
the actual fork-built executables. The CPU suite compiles, assembles, and
executes 20 amd64 programs. TinyCC parity compares expanded C, HCCIR, and M1
for TinyCC and both support units against **both** faithful HCC and direct
GHC HCC. These tests are included in `nix flake check` on x86_64 Linux.

`tinycc.ghc.precisely.grammar-gcc-debug` additionally runs the normal TinyCC
self-hosting recipe, including real version output, whole-executable
stage2/stage3 comparison, and compiled-program execution. It is also included
as `checks.x86_64-linux.m2-grammar-tinycc-selfhost`. This is a host/debug
compiler route, not a seed-only bootstrap. Only amd64 Linux is validated;
no fork-built Blynn ladder, later GCC/glibc builds, or full C conformance is
claimed.
