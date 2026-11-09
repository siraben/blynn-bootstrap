#!/usr/bin/env sh
set -eu

repo_dir=${1:-$(CDPATH= cd "$(dirname "$0")/.." && pwd)}
repo_dir=$(CDPATH= cd "$repo_dir" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
src="$work/mes"
mkdir -p "$src/build-aux" "$src/include/linux/x86_64" \
  "$src/lib/x86_64-mes-gcc" "$src/lib/linux/x86_64-mes-gcc" "$src/lib/posix"
for name in kernel-stat signal syscall; do
  printf 'header %s\n' "$name" > "$src/include/linux/x86_64/$name.h"
done
for name in crt1 crti crtn; do
  printf 'startup %s\n' "$name" > "$src/lib/linux/x86_64-mes-gcc/$name.c"
done
printf 'getopt\n' > "$src/lib/posix/getopt.c"
for name in strtod ldexp setjmp config; do
  printf 'replacement %s\n' "$name" > "$work/$name"
done
excluded='lib/mes/abtod.c lib/stdlib/strtod.c lib/stdlib/strtof.c lib/stdlib/strtold.c lib/stub/ldexp.c'

fixture() {
  printf "libc_gnu_SOURCES='%s'\n" "$*" > "$src/build-aux/configure-lib.sh"
  for rel in "$@"; do
    mkdir -p "$src/${rel%/*}"
    printf '%s\n' "$rel" > "$src/$rel"
  done
}
run() {
  env GNU_MES_DIR="$src" OUT_DIR="$work/out" MES_LIBC_ARCH="${1:-x86_64}" \
    MES_STRTOD_SOURCE="$work/strtod" MES_LDEXP_SOURCE="$work/ldexp" \
    MES_SETJMP_SOURCE="$work/setjmp" MES_CONFIG_SOURCE="$work/config" \
    sh "$repo_dir/scripts/prepare-mes-libc.sh"
}
check_output() {
  cmp "$work/expected" "$work/out/lib/libc.c"
  cmp "$work/setjmp" "$work/out/lib/x86_64-mes-gcc/setjmp.c"
  cmp "$work/config" "$work/out/include/mes/config.h"
  cmp "$src/include/linux/x86_64/kernel-stat.h" "$work/out/include/arch/kernel-stat.h"
  for name in crt1 crti crtn; do
    cmp "$src/lib/linux/x86_64-mes-gcc/$name.c" "$work/out/lib/$name.c"
  done
  cmp "$src/lib/posix/getopt.c" "$work/out/lib/libgetopt.c"
}
# A short list used to silently omit both replacements. All five upstream
# definitions must be excluded, regardless of their position around the anchor.
# shellcheck disable=SC2086
fixture lib/before.c $excluded lib/linux/uname.c lib/after.c
printf '%s\n' lib/before.c 'replacement strtod' 'replacement ldexp' \
  lib/linux/uname.c lib/after.c > "$work/expected"
run
check_output

# Move unrelated entries across the old ordinal boundary and then reorder them.
markers=
i=1
while [ "$i" -le 105 ]; do
  markers="$markers lib/marker-$i.c"
  i=$((i + 1))
done
for order in before after; do
  : > "$work/expected"
  if [ "$order" = before ]; then
    # shellcheck disable=SC2086
    fixture $markers lib/linux/uname.c $excluded lib/tail.c
    for rel in $markers; do printf '%s\n' "$rel" >> "$work/expected"; done
  else
    # shellcheck disable=SC2086
    fixture lib/linux/uname.c $excluded $markers lib/tail.c
  fi
  printf '%s\n' 'replacement strtod' 'replacement ldexp' lib/linux/uname.c >> "$work/expected"
  if [ "$order" = after ]; then
    for rel in $markers; do printf '%s\n' "$rel" >> "$work/expected"; done
  fi
  printf '%s\n' lib/tail.c >> "$work/expected"
  run
  check_output
done

reject() {
  message=$1
  shift
  if run "$@" > "$work/rejected.log" 2>&1; then
    printf 'Mes preparation unexpectedly accepted: %s\n' "$message" >&2
    exit 1
  fi
  grep -F "$message" "$work/rejected.log"
}
fixture lib/before.c lib/after.c
reject 'missing Mes libc insertion anchor: lib/linux/uname.c'
test ! -e "$work/out/lib/libc.c"
test ! -e "$work/out/lib/libc.c.tmp"
fixture lib/linux/uname.c lib/between.c lib/linux/uname.c
reject 'repeated Mes libc insertion anchor: lib/linux/uname.c'
test ! -e "$work/out/lib/libc.c"
test ! -e "$work/out/lib/libc.c.tmp"
for arch in x86 i686 i386; do
  reject 'Mes replacements require LP64 and x86_64 setjmp' "$arch"
done
for arch in aarch64 arm64 bogus; do
  reject "unsupported MES_LIBC_ARCH: $arch" "$arch"
done
printf 'Mes libc preparation: OK\n'
