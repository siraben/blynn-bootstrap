#!/usr/bin/env sh
set -eu

repo_dir=${1:-$(CDPATH= cd "$(dirname "$0")/.." && pwd)}
repo_dir=$(CDPATH= cd "$repo_dir" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
shell=$(command -v sh)
. "$repo_dir/data/bootstrap-sources.env"

mkdir -p "$work/path" "$work/cache" "$work/upstream"
for tool in chmod cp find mkdir rm sed; do
  ln -s "$(command -v "$tool")" "$work/path/$tool"
done
# These tests cover source selection, not patch contents or downloading.
printf '#!%s\nexit 0\n' "$shell" > "$work/path/patch"
printf '#!%s\nexit 99\n' "$shell" > "$work/path/curl"
chmod +x "$work/path/patch" "$work/path/curl"

stamp() {
  mkdir -p "$work/cache/$1"
  printf '%s\n' "$2" > "$work/cache/$1/.bootstrap-rev"
  printf 'pinned %s\n' "$1" > "$work/cache/$1/marker"
}
stamp oriansj-blynn-compiler "$ORIANSJ_BLYNN_COMPILER_REV"
stamp oriansj-blynn-compiler/M2libc "$ORIANSJ_BLYNN_COMPILER_M2LIBC_REV"
stamp blynn-compiler "$BLYNN_COMPILER_REV"
stamp janneke-tinycc "$JANNEKE_TINYCC_REV"
stamp gnu-mes "$GNU_MES_REV"
for name in oriansj-blynn-compiler blynn-compiler janneke-tinycc gnu-mes; do
  mkdir -p "$work/upstream/$name"
  printf 'local %s\n' "$name" > "$work/upstream/$name/marker"
done
mkdir -p "$work/upstream/oriansj-blynn-compiler/M2libc"
printf 'local libc\n' > "$work/upstream/oriansj-blynn-compiler/M2libc/marker"

run() (
  cd "$work"
  env PATH="$work/path" OUT_DIR="$work/out" SOURCE_CACHE_DIR="$work/cache" \
    BOOTSTRAP_SOURCE_PINS="$repo_dir/data/bootstrap-sources.env" \
    ORIANSJ_BLYNN_DIR= BLYNN_DIR= TINYCC_DIR= GNU_MES_DIR= \
    "$@" "$shell" "$repo_dir/scripts/prepare-upstreams.sh"
)

run
for name in oriansj-blynn-compiler blynn-compiler janneke-tinycc gnu-mes; do
  cmp "$work/cache/$name/marker" "$work/out/$name/marker"
done
run ORIANSJ_BLYNN_DIR=upstream/oriansj-blynn-compiler \
  BLYNN_DIR=upstream/blynn-compiler TINYCC_DIR=upstream/janneke-tinycc \
  GNU_MES_DIR=upstream/gnu-mes
for name in oriansj-blynn-compiler blynn-compiler janneke-tinycc gnu-mes; do
  cmp "$work/upstream/$name/marker" "$work/out/$name/marker"
done
if run BLYNN_DIR=does-not-exist > "$work/rejected.log" 2>&1; then
  printf 'missing source override unexpectedly accepted\n' >&2
  exit 1
fi
grep -F 'missing local source override' "$work/rejected.log"
printf 'bootstrap source selection: OK\n'
