#!/usr/bin/env sh

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
    i386 | i486 | i586 | i686) echo x86 ;;
    riscv32) echo riscv32 ;;
    riscv64) echo riscv64 ;;
    *)
      echo "bootstrap: error: unsupported host architecture; set M2_ARCH" >&2
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
: "${OUT_DIR:=build}"
case $OUT_DIR in
  /*) ;;
  *) OUT_DIR=$(pwd)/$OUT_DIR ;;
esac
M2_ARCH=$ARCH
M2_OS=$OPERATING_SYSTEM
SCRIPT_DIR=$script_dir
export ARCH OPERATING_SYSTEM M2_ARCH M2_OS OUT_DIR SCRIPT_DIR
sh "$script_dir/bootstrap-blynn.kaem"
"$OUT_DIR/tinycc-boot-hcc/bin/tcc" -version
