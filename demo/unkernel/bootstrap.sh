#!/bin/sh
set -eu
root=$(CDPATH= cd "$(dirname "$0")" && pwd)
cd "$root/source"
tcc_include_src="$PWD/include"
mes_include_src="$root/mes-include"
tcc_sysinclude_path=/bootstrap/mes-include
tcc_target_define_arg=-DTCC_TARGET_ARM64=1
tcc_riscv64_no_asm_define_arg=
tcc_version=$(head -n 1 "$root/version")
bootstrap_link_prefix='-nostdlib bootstrap-libs/crt1.o bootstrap-libs/crti.o'
bootstrap_link_suffix='bootstrap-libs/aarch64-runtime.o bootstrap-libs/aarch64-syscalls.o bootstrap-libs/tcc-bootstrap-support.o bootstrap-libs/libgetopt.o bootstrap-libs/libtcc1.o bootstrap-libs/lib-arm64.o bootstrap-libs/crtn.o'
run_target() { "$@"; }
. "$root/self-build.sh"
self_build "$root/tcc-hcc-stage1" ./tcc-stage2
self_build ./tcc-stage2 ./tcc-stage3
self_build ./tcc-stage3 ./tcc-stage4
cmp ./tcc-stage3 ./tcc-stage4
sha256sum ./tcc-stage3 ./tcc-stage4
printf '%s\n' 'TinyCC stage 3/4 fixpoint verified.'
