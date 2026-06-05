#!/bin/sh
# Sourced by compiler smoke checks in both GHC and actual M2 builds.
# Only POSIX shell builtins: no host compiler or extra faithful-path tools.

contract_equal() {
  if test "$1" != "$2"; then
    printf 'target-contract: expected [%s], got [%s]\n' "$1" "$2" >&2
    exit 1
  fi
}

contract_backend_fail() {
  diagnostic=$1
  shift
  if "$HCC_M1" "$@" target-contract.hccir target-contract.M1 2>target-contract.err; then
    echo 'target-contract: backend unexpectedly accepted invalid IR' >&2
    exit 1
  fi
  expect_file_contains "$diagnostic" target-contract.err
}

log 'START target metadata contract'
printf 'long width(void) { return sizeof(long); }\n' > target-contract.i
for alias in amd64 x86_64 i386 x86 aarch64 arm64 riscv64; do
  case "$alias" in
    amd64|x86_64) canonical=amd64; word=8 ;;
    i386|x86) canonical=i386; word=4 ;;
    aarch64|arm64) canonical=aarch64; word=8 ;;
    riscv64) canonical=riscv64; word=8 ;;
  esac
  "$HCC1" --target "$alias" --m1-ir -o target-contract.hccir target-contract.i
  {
    IFS= read -r line; contract_equal 'HCCIR 1' "$line"
    IFS= read -r line; contract_equal "T $canonical" "$line"
    IFS= read -r line; contract_equal 'F width' "$line"
    IFS= read -r line; contract_equal 'L 0' "$line"
    IFS= read -r line; contract_equal "3 0 $word" "$line"
    if test "$word" = 4; then
      IFS= read -r line; contract_equal '22 1 4 T0' "$line"
      IFS= read -r line; contract_equal 'R T1' "$line"
    else
      IFS= read -r line; contract_equal 'R T0' "$line"
    fi
    IFS= read -r line; contract_equal 'E' "$line"
    if IFS= read -r line; then echo 'unexpected extra IR' >&2; exit 1; fi
  } < target-contract.hccir
  "$HCC_M1" target-contract.hccir target-contract.M1
  case "$canonical" in i386) assembly_arch=x86 ;; *) assembly_arch=$canonical ;; esac
  expect_file_contains "## target: stage0-posix $assembly_arch M1" target-contract.M1
  "$HCC_M1" --target "$alias" target-contract.hccir target-contract.M1
  # Metadata aliases have exactly the same meaning as CLI aliases.
  printf 'HCCIR 1\nT %s\nF width\nL 0\nR I%s\nE\n' "$alias" "$word" > target-contract.hccir
  "$HCC_M1" --target "$canonical" target-contract.hccir target-contract.M1
  case "$canonical" in amd64) other=aarch64 ;; *) other=amd64 ;; esac
  printf 'sentinel\n' > target-contract.M1
  contract_backend_fail 'does not match --target' --target "$other"
  IFS= read -r line < target-contract.M1; contract_equal sentinel "$line"
done

# Empty modules are valid, but metadata-free legacy IR is never guessed.
printf 'HCCIR 1\nT i386\n' > target-contract.hccir
"$HCC_M1" target-contract.hccir target-contract.M1
expect_file_contains '## target: stage0-posix x86 M1' target-contract.M1
printf 'HCCIR 1\n' > target-contract.hccir
contract_backend_fail 'missing HCCIR target record'
contract_backend_fail 'missing HCCIR target record' --target amd64
for body in '' 'F width' 'D data' 'T'; do
  printf 'HCCIR 1\n%s\n' "$body" > target-contract.hccir
  contract_backend_fail 'missing HCCIR target record'
  contract_backend_fail 'missing HCCIR target record' --target amd64
done
for record in 'T unknown' 'T amd64 64' 'T i386 64' 'T ' 'T amd64 extra' 'T  amd64'; do
  printf 'HCCIR 1\n%s\n' "$record" > target-contract.hccir
  contract_backend_fail 'unknown target'
done
printf 'HCCIR 2\nT amd64\n' > target-contract.hccir
contract_backend_fail 'bad IR input header'
printf 'HCCIR 1\nT amd64\nT amd64\n' > target-contract.hccir
contract_backend_fail 'duplicate or misplaced'
printf 'HCCIR 1\nT amd64\nF width\nL 0\nR I8\nE\nT amd64\n' > target-contract.hccir
contract_backend_fail 'duplicate or misplaced'
printf 'HCCIR 1\nF width\nL 0\nR I8\nE\nT amd64\n' > target-contract.hccir
contract_backend_fail 'missing HCCIR target record'
printf 'HCCIR 1\nT amd64\nF width\nT amd64\nE\n' > target-contract.hccir
contract_backend_fail 'IR'
printf 'HCCIR 1\nT amd64\nD data\nT amd64\nE\n' > target-contract.hccir
contract_backend_fail 'IR'
contract_backend_fail 'unknown target' --target unknown

for target in amd64 i386 aarch64 riscv64; do
  case "$target" in i386) word=4 ;; *) word=8 ;; esac
  for type in 'void *' long 'unsigned long' int 'long long'; do
    case "$type" in int) size=4 ;; 'long long') size=8 ;; *) size=$word ;; esac
    printf 'int width(void) { return sizeof(%s); }\n' "$type" > target-contract.i
    "$HCC1" --target "$target" --m1-ir -o target-contract.hccir target-contract.i
    expect_file_contains "3 0 $size" target-contract.hccir
  done
done

# The default target is stable; failed lowering must not publish its header
# or partial IR, including when a previous function emitted.
printf 'int ok(void) { return 7; }\n' > target-contract.i
"$HCC1" --m1-ir -o target-contract.hccir target-contract.i
expect_file_contains 'T amd64' target-contract.hccir
# Repeated frontend selectors follow the existing last-option-wins rule.
"$HCC1" --target amd64 --target x86 --m1-ir -o target-contract.hccir target-contract.i
expect_file_contains 'T i386' target-contract.hccir
if "$HCC1" target-contract.i --target 2>target-contract.err; then
  echo 'target-contract: frontend accepted missing target argument' >&2
  exit 1
fi
expect_file_contains 'requires an argument' target-contract.err
printf 'int bad(void) { return missing_name; }\n' >> target-contract.i
printf 'sentinel\n' > target-contract.hccir
if "$HCC1" --target i386 --m1-ir -o target-contract.hccir target-contract.i 2>target-contract.err; then
  echo 'target-contract: frontend unexpectedly accepted invalid C' >&2
  exit 1
fi
expect_file_contains 'unknown identifier' target-contract.err
if test -s target-contract.hccir; then
  echo 'target-contract: frontend published partial IR' >&2
  exit 1
fi
printf 'sentinel\n' > target-contract.hccir
if "$HCC1" --target unknown --m1-ir -o target-contract.hccir target-contract.i 2>target-contract.err; then
  echo 'target-contract: frontend unexpectedly accepted unknown target' >&2
  exit 1
fi
expect_file_contains 'unsupported target' target-contract.err
IFS= read -r line < target-contract.hccir; contract_equal sentinel "$line"
log 'DONE target metadata contract'
