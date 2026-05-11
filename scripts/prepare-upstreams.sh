#!/bin/sh

set -eu

case $0 in
  */*) script_path=$0 ;;
  *) script_path=$(command -v "$0") || exit 1 ;;
esac
script_dir=${script_path%/*}
[ "$script_dir" = "$script_path" ] && script_dir=.
script_dir=$(CDPATH= cd "$script_dir" && pwd)
repo_dir=$(CDPATH= cd "$script_dir/.." && pwd)
. "$script_dir/lib/bootstrap.sh"

require_cmd cp
require_cmd mkdir
require_cmd patch
require_cmd rm

out_dir=${OUT_DIR:-build/upstreams}
oriansj_src=${ORIANSJ_BLYNN_DIR:-${1:-upstream/oriansj-blynn-compiler}}
blynn_src=${BLYNN_DIR:-${2:-upstream/blynn-compiler}}
tinycc_src=${TINYCC_DIR:-${3:-}}

if [ -z "$tinycc_src" ] && [ -d "$repo_dir/upstream/tinycc" ]; then
  tinycc_src=$repo_dir/upstream/tinycc
fi

out_dir=$(abspath "$out_dir")
oriansj_src=$(abspath "$oriansj_src")
blynn_src=$(abspath "$blynn_src")
[ -z "$tinycc_src" ] || tinycc_src=$(abspath "$tinycc_src")

[ -d "$oriansj_src" ] || die "missing OriansJ Blynn source: $oriansj_src"
[ -d "$blynn_src" ] || die "missing Blynn compiler source: $blynn_src"
[ -z "$tinycc_src" ] || [ -d "$tinycc_src" ] || die "missing TinyCC source: $tinycc_src"

mkdir -p "$out_dir"

copy_upstream() {
  name=$1
  src=$2
  dest=$out_dir/$name

  msg "prepare $name"
  rm -rf "$dest"
  cp -R "$src" "$dest"
  chmod -R u+w "$dest"
}

patch_upstream() {
  dest=$1
  patch_file=$2

  (
    cd "$dest"
    patch -p1 < "$patch_file"
  )
}

copy_upstream \
  oriansj-blynn-compiler \
  "$oriansj_src"

copy_upstream \
  blynn-compiler \
  "$blynn_src"
patch_upstream \
  "$out_dir/blynn-compiler" \
  "$repo_dir/patches/upstreams/blynn-compiler-local.patch"

if [ -n "$tinycc_src" ]; then
  copy_upstream \
    tinycc \
    "$tinycc_src"
  patch_upstream \
    "$out_dir/tinycc" \
    "$repo_dir/patches/upstreams/tinycc-mescc-source.patch"
fi

msg "patched upstreams are in $out_dir"
