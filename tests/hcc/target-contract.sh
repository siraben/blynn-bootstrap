#!/bin/sh
# Sourced by compiler smoke checks in both GHC and actual M2 builds.
# Only POSIX shell builtins: no host compiler or extra faithful-path tools.

contract_equal() {
  if test "$1" != "$2"; then
    printf 'target-contract: expected [%s], got [%s]\n' "$1" "$2" >&2
    exit 1
  fi
}

contract_fail() {
  diagnostic=$1
  shift
  if "$@" 2>target-contract.err; then
    echo 'target-contract: unexpectedly accepted invalid input' >&2
    exit 1
  fi
  expect_file_contains "$diagnostic" target-contract.err
}

contract_backend_fail() {
  diagnostic=$1
  shift
  contract_fail "$diagnostic" "$HCC_M1" "$@" target-contract.hccir target-contract.M1
}

log 'START target metadata contract'
printf 'long width(void) { return sizeof(long); }\n' > target-contract.i
# Representative 32/64-bit aliases, canonical metadata and backend inference.
# Runtime layout/pointer widths for all targets live in m1-smoke/target-widths.
for alias in x86 arm64; do
  case "$alias" in
    x86) canonical=i386; word=4; assembly_arch=x86 ;;
    arm64) canonical=aarch64; word=8; assembly_arch=aarch64 ;;
  esac
  "$HCC1" --target "$alias" --m1-ir -o target-contract.hccir target-contract.i
  expect_file_contains "T $canonical" target-contract.hccir
  expect_file_contains "3 0 $word" target-contract.hccir
  "$HCC_M1" target-contract.hccir target-contract.M1
  expect_file_contains "## target: stage0-posix $assembly_arch M1" target-contract.M1
done
# Even two 64-bit architectures must not match; reject before opening output.
printf 'sentinel\n' > target-contract.M1
contract_backend_fail 'does not match --target' --target amd64
IFS= read -r line < target-contract.M1; contract_equal sentinel "$line"
# Metadata aliases also agree with explicit canonical CLI selectors.
printf 'HCCIR 1\nT x86\n' > target-contract.hccir
"$HCC_M1" --target i386 target-contract.hccir target-contract.M1

# Legacy IR is never guessed, even with an explicit target.
printf 'HCCIR 1\n' > target-contract.hccir
contract_backend_fail 'missing HCCIR target record'
printf 'HCCIR 1\nF width\n' > target-contract.hccir
contract_backend_fail 'missing HCCIR target record' --target amd64
for record in 'T unknown' 'T amd64 extra'; do
  printf 'HCCIR 1\n%s\n' "$record" > target-contract.hccir
  contract_backend_fail 'unknown target'
done
printf 'HCCIR 2\nT amd64\n' > target-contract.hccir
contract_backend_fail 'bad IR input header'
printf 'HCCIR 1\nT amd64\nT amd64\n' > target-contract.hccir
contract_backend_fail 'duplicate or misplaced'
printf 'HCCIR 1\nT amd64\nF width\nT amd64\nE\n' > target-contract.hccir
contract_backend_fail 'IR'
contract_backend_fail 'unknown target' --target unknown

# Default/last-option-wins selection and failures must not publish partial IR.
"$HCC1" --m1-ir -o target-contract.hccir target-contract.i
expect_file_contains 'T amd64' target-contract.hccir
"$HCC1" --target amd64 --target x86 --m1-ir -o target-contract.hccir target-contract.i
expect_file_contains 'T i386' target-contract.hccir
contract_fail 'requires an argument' "$HCC1" target-contract.i --target
printf 'int bad(void) { return missing_name; }\n' >> target-contract.i
printf 'sentinel\n' > target-contract.hccir
contract_fail 'unknown identifier' "$HCC1" --target i386 --m1-ir -o target-contract.hccir target-contract.i
if test -s target-contract.hccir; then
  echo 'target-contract: frontend published partial IR' >&2
  exit 1
fi
printf 'sentinel\n' > target-contract.hccir
contract_fail 'unsupported target' "$HCC1" --target unknown --m1-ir -o target-contract.hccir target-contract.i
IFS= read -r line < target-contract.hccir; contract_equal sentinel "$line"
log 'DONE target metadata contract'
