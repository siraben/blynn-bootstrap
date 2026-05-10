#!/bin/sh

set -eu

case $0 in
  */*) script_path=$0 ;;
  *) script_path=$(command -v "$0") || exit 1 ;;
esac
script_dir=${script_path%/*}
[ "$script_dir" = "$script_path" ] && script_dir=.
script_dir=$(CDPATH= cd "$script_dir" && pwd)

base_out=${OUT_DIR:-build}
upstream_out=${UPSTREAM_OUT_DIR:-$base_out/upstreams}
root_out=${BLYNN_ROOT_OUT_DIR:-$base_out/blynn-root}
precisely_out=${BLYNN_PRECISELY_OUT_DIR:-$base_out/blynn-precisely}

ORIANSJ_BLYNN_DIR=${ORIANSJ_BLYNN_DIR:-upstream/oriansj-blynn-compiler} \
BLYNN_DIR=${BLYNN_DIR:-upstream/blynn-compiler} \
OUT_DIR=$upstream_out \
  "$script_dir/prepare-upstreams.sh"

ORIANSJ_BLYNN_DIR=$upstream_out/oriansj-blynn-compiler \
OUT_DIR=$root_out \
  "$script_dir/bootstrap-blynn-root.sh"

BLYNN_DIR=$upstream_out/blynn-compiler \
METHODICALLY=$root_out/bin/methodically \
OUT_DIR=$precisely_out \
  "$script_dir/bootstrap-blynn-precisely.sh"
