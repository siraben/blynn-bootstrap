#!/bin/sh
set -eu
sh /seed/stage0.sh
cd /seed/repo
export M2_ARCH=aarch64 M2_OS=Linux
export PATH=/seed/AArch64/bin:$PATH
export M2LIBC_PATH=/seed/M2libc
export CROSSLY_TOP=67108864 HCPP_TOP=67108864 HCC1_TOP=67108864
export HCC_RTS_ADAPTIVE_MAJOR_WORDS=33554432
build=/seed/build
export ORIANSJ_BLYNN_DIR=/seed/upstreams/oriansj
export BLYNN_DIR=/seed/upstreams/blynn
export MES_LIBC_DIR=/seed/upstreams/mes-libc
export TINYCC_DIR=/seed/upstreams/tinycc
OUT_DIR=$build/root sh scripts/bootstrap-blynn-root.sh
METHODICALLY=$build/root/bin/methodically OUT_DIR=$build/precisely sh scripts/bootstrap-blynn-precisely.sh
export BLYNN_COMPILER=$build/precisely/bin/crossly1
export HCC_BLYNN_SOURCES_DIR=$build/sources
OUT_DIR=$HCC_BLYNN_SOURCES_DIR sh scripts/hcc-blynn-sources.sh
export HCC_BLYNN_OBJECTS_DIR=$build/objs
export MATERIALIZE_OBJECT_SCRIPT=$build/materialize-object-script
M2-Mesoplanet --operating-system Linux --architecture aarch64 \
  -f hcc/support/materialize-object-script.c -o "$MATERIALIZE_OBJECT_SCRIPT"
OUT_DIR=$HCC_BLYNN_OBJECTS_DIR sh scripts/hcc-blynn-objs.sh
export HCC_BLYNN_C_DIR=$build/c
OUT_DIR=$HCC_BLYNN_C_DIR sh scripts/hcc-blynn-c.sh
export HCC_BIN_DIR=$build/hcc
OUT_DIR=$HCC_BIN_DIR sh scripts/hcc-blynn-bin.sh
OUT_DIR=$build/tinycc sh scripts/tinycc-boot-hcc.sh
"$build/tinycc/bin/tcc" -dumpversion
sha256sum "$build/tinycc/bin/tcc"
printf '%s\n' 'Seed → Blynn → HCC → TinyCC verified.'
