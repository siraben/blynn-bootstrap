#!/usr/bin/env sh

set -eu

case $0 in
  */*) script_path=$0 ;;
  *) script_path=$(command -v "$0") || exit 1 ;;
esac
script_dir=${script_path%/*}
[ "$script_dir" = "$script_path" ] && script_dir=.
script_dir=$(CDPATH= cd "$script_dir" && pwd)

: "${ARCH:=${M2_ARCH:-amd64}}"
: "${OPERATING_SYSTEM:=${M2_OS:-Linux}}"
: "${OUT_DIR:=build}"
case $OUT_DIR in
  /*) ;;
  *) OUT_DIR=$(pwd)/$OUT_DIR ;;
esac
M2_ARCH=$ARCH
M2_OS=$OPERATING_SYSTEM
SCRIPT_DIR=$script_dir
export ARCH OPERATING_SYSTEM M2_ARCH M2_OS OUT_DIR SCRIPT_DIR
exec sh "$script_dir/bootstrap-blynn.kaem"
