#!/usr/bin/env sh
# Portable CCC bootstrap: stage0 tools -> CCC toolchain -> TinyCC, with no
# host C compiler and no package manager beyond what fetches the sources.
# On a fresh Alpine container:
#   apk add --no-cache ca-certificates wget patch
#   M2_ARCH=amd64 M2_OS=Linux sh scripts/bootstrap-ccc.sh
# Outputs build/tinycc-boot-ccc/bin/tcc.

set -eu

case $0 in
  */*) script_path=$0 ;;
  *) script_path=$(command -v "$0") || exit 1 ;;
esac
script_dir=${script_path%/*}
[ "$script_dir" = "$script_path" ] && script_dir=.
script_dir=$(CDPATH= cd "$script_dir" && pwd)

bootstrap_arch() {
  case $(uname -m 2>/dev/null || echo unknown) in
    amd64 | x86_64) echo amd64 ;;
    aarch64 | arm64) echo aarch64 ;;
    *)
      echo "bootstrap-ccc: error: unsupported host architecture; set M2_ARCH" >&2
      exit 1
      ;;
  esac
}

if [ "${ARCH:-}" ]; then
  :
elif [ "${M2_ARCH:-}" ]; then
  ARCH=$M2_ARCH
else
  ARCH=$(bootstrap_arch)
fi
: "${OPERATING_SYSTEM:=${M2_OS:-Linux}}"
: "${BOOTSTRAP_OUT:=build}"
case $BOOTSTRAP_OUT in
  /*) ;;
  *) BOOTSTRAP_OUT=$(pwd)/$BOOTSTRAP_OUT ;;
esac
M2_ARCH=$ARCH
M2_OS=$OPERATING_SYSTEM
export ARCH OPERATING_SYSTEM M2_ARCH M2_OS

UPSTREAM=$BOOTSTRAP_OUT/upstreams
TOOLS=$BOOTSTRAP_OUT/bootstrap-tools
MES_LIBC=$BOOTSTRAP_OUT/mes-libc
CCC_CHAIN=$BOOTSTRAP_OUT/ccc-chain
TINYCC=$BOOTSTRAP_OUT/tinycc-boot-ccc

OUT_DIR=$UPSTREAM
export OUT_DIR
sh "$script_dir/prepare-upstreams.sh"

OUT_DIR=$TOOLS
export OUT_DIR
sh "$script_dir/bootstrap-tools.sh"

PATH=$TOOLS/bin:$PATH
M2LIBC_PATH=$TOOLS/artifact/stage0-posix/M2libc
export PATH M2LIBC_PATH

GNU_MES_DIR=$UPSTREAM/gnu-mes
OUT_DIR=$MES_LIBC
export GNU_MES_DIR OUT_DIR
sh "$script_dir/prepare-mes-libc.sh"

OUT_DIR=$CCC_CHAIN
export OUT_DIR
sh "$script_dir/ccc-chain.sh"

TINYCC_DIR=$UPSTREAM/janneke-tinycc
HCC_BIN_DIR=$CCC_CHAIN
MES_LIBC_DIR=$MES_LIBC
OUT_DIR=$TINYCC
export TINYCC_DIR HCC_BIN_DIR MES_LIBC_DIR M2LIBC_PATH OUT_DIR
sh "$script_dir/tinycc-boot-hcc.sh"

printf 'ccc-bootstrapped tcc version %s\n' "$("$TINYCC/bin/tcc" -dumpversion)"
