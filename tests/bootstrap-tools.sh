#!/usr/bin/env sh
set -eu

repo_dir=${1:-$(CDPATH= cd "$(dirname "$0")/.." && pwd)}
repo_dir=$(CDPATH= cd "$repo_dir" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
shell=$(command -v sh)
. "$repo_dir/data/bootstrap-sources.env"

# Isolate PATH so neither a real compiler nor a network fetch can hide a skip.
mkdir -p "$work/path" "$work/cache/stage0-posix" "$work/libc"
for tool in chmod cp find ln mkdir mv rm sed sha256sum; do
  ln -s "$(command -v "$tool")" "$work/path/$tool"
done
printf '#!%s\nexit 99\n' "$shell" > "$work/path/curl"
chmod +x "$work/path/curl"
for tool in M2-Mesoplanet M2-Planet blood-elf M1 hex2 kaem; do
  printf '#!%s\nexit 98\n' "$shell" > "$work/path/$tool"
  chmod +x "$work/path/$tool"
done
: > "$work/libc/bootstrappable.h"

cache=$work/cache/stage0-posix
stamp() {
  mkdir -p "$cache/$1"
  printf '%s\n' "$2" > "$cache/$1/.bootstrap-rev"
}
stamp . "$STAGE0_POSIX_REV"
stamp AMD64 "$STAGE0_POSIX_AMD64_REV"
stamp M2-Mesoplanet "$STAGE0_M2_MESOPLANET_REV"
stamp M2-Planet "$STAGE0_M2_PLANET_REV"
stamp M2libc "$STAGE0_M2LIBC_REV"
stamp bootstrap-seeds "$STAGE0_BOOTSTRAP_SEEDS_REV"
stamp mescc-tools "$MESCC_TOOLS_REV"
stamp mescc-tools-extra "$STAGE0_MESCC_TOOLS_EXTRA_REV"
printf '# Phase 16-23 unused in fixture\n' > "$cache/AMD64/kaem.run"
mkdir -p "$cache/bootstrap-seeds/POSIX/AMD64" "$cache/AMD64/expected"
: > "$cache/amd64.answers"
for tool in M2-Mesoplanet M2-Planet blood-elf M1 hex2 kaem; do
  printf 'seed-built %s\n' "$tool" > "$cache/AMD64/expected/$tool"
  hash=$(sha256sum "$cache/AMD64/expected/$tool")
  printf '%s  AMD64/bin/%s\n' "${hash%% *}" "$tool" >> "$cache/amd64.answers"
done
{
  printf '#!%s\n' "$shell"
  printf '%s\n' 'set -eu' 'mkdir -p AMD64/bin' \
    'cp AMD64/expected/* AMD64/bin/' 'chmod +x AMD64/bin/*' \
    'if [ "${CORRUPT_SEED:-0}" = 1 ]; then printf bad > AMD64/bin/M1; fi'
} > "$cache/bootstrap-seeds/POSIX/AMD64/kaem-optional-seed"
chmod +x "$cache/bootstrap-seeds/POSIX/AMD64/kaem-optional-seed"

run() {
  env PATH="$work/path" M2_ARCH=amd64 OUT_DIR="$work/out" \
    SOURCE_CACHE_DIR="$work/cache" BOOTSTRAP_SOURCE_PINS="$repo_dir/data/bootstrap-sources.env" \
    BOOTSTRAP_TOOLS_FROM_PATH=0 BOOTSTRAP_TOOLS_REBUILD=0 BOOTSTRAP_TOOLS_FULL=0 \
    M2LIBC_PATH= CORRUPT_SEED=0 "$@" "$shell" "$repo_dir/scripts/bootstrap-tools.sh"
}
reject() {
  expected=$1
  shift
  if run "$@" > "$work/rejected.log" 2>&1; then
    printf 'unexpected success: %s\n' "$*" >&2
    exit 1
  fi
  grep -F "$expected" "$work/rejected.log"
}

# A complete PATH toolchain must not change the default to reuse mode.
run
for tool in M2-Mesoplanet M2-Planet blood-elf M1 hex2 kaem; do
  test ! -L "$work/out/bin/$tool"
  cmp "$cache/AMD64/expected/$tool" "$work/out/bin/$tool"
done
run BOOTSTRAP_TOOLS_REBUILD=1
run BOOTSTRAP_TOOLS_FULL=1
reject FAILED CORRUPT_SEED=1
reject FAILED CORRUPT_SEED=1 BOOTSTRAP_TOOLS_FULL=1
cp "$cache/amd64.answers" "$work/answers"
sed '/  AMD64\/bin\/M1$/d' "$work/answers" > "$cache/amd64.answers"
reject 'missing stage0 answer'
cp "$work/answers" "$cache/amd64.answers"
rm "$work/path/sha256sum"
reject 'missing required command: sha256sum'

reject 'requires M2LIBC_PATH' BOOTSTRAP_TOOLS_FROM_PATH=1
reject 'must be 0 or 1' BOOTSTRAP_TOOLS_FROM_PATH=yes
reject 'cannot combine' BOOTSTRAP_TOOLS_FROM_PATH=1 BOOTSTRAP_TOOLS_REBUILD=1
run BOOTSTRAP_TOOLS_FROM_PATH=1 M2LIBC_PATH="$work/libc"
for tool in M2-Mesoplanet M2-Planet blood-elf M1 hex2 kaem; do
  test -L "$work/out/bin/$tool"
  cmp "$work/path/$tool" "$work/out/bin/$tool"
done
reject 'cannot reuse' BOOTSTRAP_TOOLS_FROM_PATH=1 M2LIBC_PATH="$work/libc" PATH="$work/out/bin:$work/path"
rm "$work/path/blood-elf"
reject 'requires all six' BOOTSTRAP_TOOLS_FROM_PATH=1 M2LIBC_PATH="$work/libc"
printf 'bootstrap tool selection and verification: OK\n'
