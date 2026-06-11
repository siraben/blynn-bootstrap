#!/bin/sh
set -eu

export HOME=/root
export ARCH=riscv64
export OPERATING_SYSTEM=Linux
export M2_ARCH=riscv64
export M2_OS=Linux
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export BOOTSTRAP_LOG_NAME=blynn-jslinux

repo=/bootstrap/repo
build=/work/blynn
mkdir -p "$build"
cd "$repo"

run_tinycc_from_hcc_checkpoint() {
  checkpoint=/bootstrap/checkpoints/hcc-riscv64
  [ -x "$checkpoint/bin/hcpp" ] || {
    echo "missing HCC checkpoint: $checkpoint/bin/hcpp" >&2
    exit 1
  }
  [ -x "$checkpoint/bin/hcc1" ] || {
    echo "missing HCC checkpoint: $checkpoint/bin/hcc1" >&2
    exit 1
  }
  [ -x "$checkpoint/bin/hcc-m1" ] || {
    echo "missing HCC checkpoint: $checkpoint/bin/hcc-m1" >&2
    exit 1
  }

  echo "== verified checkpoint: HCC riscv64 =="
  if [ -f "$checkpoint/SHA256SUMS" ]; then
    (cd "$checkpoint" && sha256sum -c SHA256SUMS)
  fi

  export PATH="/bootstrap/stage0-tools/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  export M2LIBC_PATH=/bootstrap/stage0-m2libc
  export TINYCC_DIR=/bootstrap/upstreams/janneke-tinycc
  export HCC_BIN_DIR="$checkpoint"
  export MES_LIBC_DIR=/bootstrap/upstreams/gnu-mes
  export HCC_TARGET=riscv64
  export TINYCC_SELFHOST=1
  export TCC_SUPPORT_OBJECT_DIR="$checkpoint/support-objects"
  export OUT_DIR="$build/tinycc-boot-hcc"

  echo "== HCC compiles TinyCC; TinyCC self-compiles to fixpoint =="
  sh scripts/tinycc-boot-hcc.sh

  echo "== resulting bootstrapped TinyCC hash =="
  cat "$OUT_DIR/tcc.sha256"
  "$OUT_DIR/bin/tcc" -dumpversion || true
  echo "blynn-tcc is available on PATH via /usr/local/bin/blynn-tcc"
}

case ${BOOTSTRAP_MODE:-checkpoint} in
  checkpoint)
    run_tinycc_from_hcc_checkpoint
    exit 0
    ;;
  from-seed) ;;
  *) echo "unknown BOOTSTRAP_MODE: ${BOOTSTRAP_MODE:-}" >&2; exit 2 ;;
esac

export SOURCE_CACHE_DIR=/bootstrap/source-cache
export BOOTSTRAP_TOOLS_REBUILD=1
export OUT_DIR="$build/bootstrap-tools"
echo "== hex0 seed to stage0-posix tools =="
sh scripts/bootstrap-tools.sh

export PATH="$build/bootstrap-tools/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export STAGE0_M2LIBC="$build/bootstrap-tools/artifact/stage0-posix/M2libc"
export M2LIBC_PATH="$STAGE0_M2LIBC"

export GNU_MES_DIR=/bootstrap/upstreams/gnu-mes
export OUT_DIR="$build/mes-libc"
echo "== prepare Mes libc =="
sh scripts/prepare-mes-libc.sh

export ORIANSJ_BLYNN_DIR=/bootstrap/upstreams/oriansj-blynn-compiler
export OUT_DIR="$build/blynn-root"
echo "== bootstrap original blynn root =="
sh scripts/bootstrap-blynn-root.sh

export BLYNN_DIR=/bootstrap/upstreams/blynn-compiler
export METHODICALLY="$build/blynn-root/bin/methodically"
export OUT_DIR="$build/blynn-precisely"
echo "== bootstrap blynn precisely =="
sh scripts/bootstrap-blynn-precisely.sh

export OUT_DIR="$build/hcc-blynn-sources"
echo "== generate HCC blynn sources =="
sh scripts/hcc-blynn-sources.sh

export PRECISELY_UP="$build/blynn-precisely/bin/precisely_up"
export HCC_BLYNN_SOURCES_DIR="$build/hcc-blynn-sources"
export MATERIALIZE_OBJECT_SCRIPT="$build/hcc-blynn-objs/materialize-object-script"
export OUT_DIR="$build/hcc-blynn-objs"
mkdir -p "$OUT_DIR"
echo "== materialize HCC blynn objects =="
M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
  -f hcc/support/materialize-object-script.c -o "$MATERIALIZE_OBJECT_SCRIPT"
chmod 555 "$MATERIALIZE_OBJECT_SCRIPT"
sh scripts/hcc-blynn-objs.sh

export HCC_BLYNN_OBJECTS_DIR="$build/hcc-blynn-objs"
export OUT_DIR="$build/hcc-blynn-c"
echo "== compile HCC C sources =="
sh scripts/hcc-blynn-c.sh

export HCC_BLYNN_C_DIR="$build/hcc-blynn-c"
export OUT_DIR="$build/hcc-blynn-bin"
export HCPP_TOP=67108864
export HCC1_TOP=67108864
export HCC_RTS_ADAPTIVE_MAJOR_WORDS=33554432
echo "== link HCC binary =="
sh scripts/hcc-blynn-bin.sh

export TINYCC_DIR=/bootstrap/upstreams/janneke-tinycc
export HCC_BIN_DIR="$build/hcc-blynn-bin"
export MES_LIBC_DIR="$build/mes-libc"
export HCC_TARGET=riscv64
export TINYCC_SELFHOST=${TINYCC_SELFHOST:-1}
export TCC_SUPPORT_OBJECT_DIR=/bootstrap/checkpoints/hcc-riscv64/support-objects
export OUT_DIR="$build/tinycc-boot-hcc"
echo "== build TinyCC with bootstrapped HCC; TinyCC self-compiles =="
sh scripts/tinycc-boot-hcc.sh

echo "== bootstrapped blynn/HCC TinyCC =="
cat "$build/tinycc-boot-hcc/tcc.sha256"
"$build/tinycc-boot-hcc/bin/tcc" -dumpversion || true
echo "blynn-tcc is available on PATH via /usr/local/bin/blynn-tcc"
