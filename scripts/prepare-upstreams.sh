#!/usr/bin/env sh

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
load_source_pins "$repo_dir"

require_cmd cp
require_cmd find
require_cmd mkdir
require_cmd patch
require_cmd rm
require_cmd sed

out_dir=${OUT_DIR:-build/upstreams}
source_cache=${SOURCE_CACHE_DIR:-build/source-cache}
oriansj_src=${ORIANSJ_BLYNN_DIR:-${1:-upstream/oriansj-blynn-compiler}}
blynn_src=${BLYNN_DIR:-${2:-upstream/blynn-compiler}}
tinycc_src=${TINYCC_DIR:-${3:-upstream/janneke-tinycc}}
gnu_mes_src=${GNU_MES_DIR:-${4:-upstream/gnu-mes}}

out_dir=$(abspath "$out_dir")
source_cache=$(abspath "$source_cache")
oriansj_src=$(abspath "$oriansj_src")
blynn_src=$(abspath "$blynn_src")
tinycc_src=$(abspath "$tinycc_src")
gnu_mes_src=$(abspath "$gnu_mes_src")

mkdir -p "$out_dir" "$source_cache"

non_empty_dir() {
  [ -d "$1" ] && [ "$(find "$1" -mindepth 1 -maxdepth 1 2>/dev/null | sed -n '1p')" ]
}

source_tree() {
  name=$1
  default_src=$2
  url=$3
  rev=$4
  archive_url=$5
  fetch_ref=${6:-}
  submodules=${7:-0}
  cache=$source_cache/$name

  if non_empty_dir "$default_src"; then
    printf '%s\n' "$default_src"
    return
  fi

  source_checkout "$name" "$url" "$rev" "$cache" "$archive_url" "$fetch_ref" "$submodules" >&2
  printf '%s\n' "$cache"
}

populate_oriansj_m2libc() {
  dest=$oriansj_src/M2libc
  if non_empty_dir "$dest"; then
    return
  fi

  source_checkout \
    oriansj-blynn-compiler-M2libc \
    "$M2LIBC_URL" \
    "$ORIANSJ_BLYNN_COMPILER_M2LIBC_REV" \
    "$dest" \
    "$ORIANSJ_BLYNN_COMPILER_M2LIBC_ARCHIVE_URL" >&2
}

oriansj_src=$(source_tree oriansj-blynn-compiler "$oriansj_src" "$ORIANSJ_BLYNN_COMPILER_URL" "$ORIANSJ_BLYNN_COMPILER_REV" "$ORIANSJ_BLYNN_COMPILER_ARCHIVE_URL")
populate_oriansj_m2libc
blynn_src=$(source_tree blynn-compiler "$blynn_src" "$BLYNN_COMPILER_URL" "$BLYNN_COMPILER_REV" "$BLYNN_COMPILER_ARCHIVE_URL")
tinycc_src=$(source_tree janneke-tinycc "$tinycc_src" "$JANNEKE_TINYCC_URL" "$JANNEKE_TINYCC_REV" "$JANNEKE_TINYCC_ARCHIVE_URL")
gnu_mes_src=$(source_tree gnu-mes "$gnu_mes_src" "$GNU_MES_URL" "$GNU_MES_REV" "$GNU_MES_ARCHIVE_URL" "${GNU_MES_FETCH_REF:-}")

prepare_upstream() {
  name=$1
  src=$2
  patch_file=${3:-}
  dest=$out_dir/$name

  msg "prepare $name"
  copy_writable_tree "$src" "$dest"
  if [ -n "$patch_file" ]; then
    (cd "$dest" && patch -p1 < "$patch_file")
  fi
}

prepare_upstream oriansj-blynn-compiler "$oriansj_src"
prepare_upstream \
  blynn-compiler "$blynn_src" \
  "$repo_dir/patches/upstreams/blynn-compiler-local.patch"
prepare_upstream \
  janneke-tinycc "$tinycc_src" \
  "$repo_dir/patches/upstreams/tinycc-mescc-source.patch"
prepare_upstream \
  gnu-mes "$gnu_mes_src" \
  "$repo_dir/patches/upstreams/gnu-mes-libc-hcc-bootstrap.patch"

msg "patched upstreams are in $out_dir"
