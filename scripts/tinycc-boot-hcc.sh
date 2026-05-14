#!/usr/bin/env sh

set -eu

case $0 in
  */*) script_path=$0 ;;
  *) script_path=$(command -v "$0") || exit 1 ;;
esac
script_dir=${script_path%/*}
[ "$script_dir" = "$script_path" ] && script_dir=.
script_dir=$(CDPATH= cd "$script_dir" && pwd)
. "$script_dir/lib/bootstrap.sh"
repo_dir=$(repo_root_from_script_dir "$script_dir")

require_cmd chmod
require_cmd cp
require_cmd mkdir
require_cmd rm
require_cmd M1
require_cmd hex2

src_dir=${TINYCC_DIR:-${1:-build/upstreams/janneke-tinycc}}
hcc_dir=${HCC_BIN_DIR:-${2:-build/hcc-blynn-bin}}
mes_libc=${MES_LIBC_DIR:-${3:-build/mes-libc}}
m2libc=${M2LIBC_PATH:-${4:-build/upstreams/oriansj-blynn-compiler/M2libc}}
out_dir=${OUT_DIR:-${5:-build/tinycc-boot-hcc}}
support_dir=${HCC_SUPPORT_DIR:-$repo_dir/hcc/support}
selfhost=${TINYCC_SELFHOST:-0}
target=${HCC_TARGET:-${TINYCC_HCC_TARGET:-${M2_ARCH:-}}}

src_dir=$(abspath "$src_dir")
hcc_dir=$(abspath "$hcc_dir")
mes_libc=$(abspath "$mes_libc")
m2libc=$(abspath "$m2libc")
out_dir=$(abspath "$out_dir")
support_dir=$(abspath "$support_dir")

if [ -z "$target" ]; then
  target=$(uname -m 2>/dev/null || printf '%s\n' amd64)
fi

case $target in
  amd64 | x86_64)
    hcc_target=amd64
    m1_arch=amd64
    m2_arch=amd64
    tcc_target_define=TCC_TARGET_X86_64
    m2_defs=amd64_defs.M1
    m2_elf=ELF-amd64.hex2
    support_start=amd64-start.M1
    support_memory=amd64-memory.M1
    support_syscalls=amd64-syscalls.M1
    support_compat=amd64-compat.M1
    base_address=0x00600000
    ;;
  aarch64 | arm64)
    hcc_target=aarch64
    m1_arch=aarch64
    m2_arch=aarch64
    tcc_target_define=TCC_TARGET_ARM64
    m2_defs=aarch64_defs.M1
    m2_elf=ELF-aarch64.hex2
    support_start=aarch64-start.M1
    support_memory=aarch64-memory.M1
    support_syscalls=aarch64-syscalls.M1
    support_compat=
    base_address=0x00600000
    [ "$selfhost" = 0 ] || die "TINYCC_SELFHOST=1 is not wired for portable aarch64 yet"
    ;;
  *) die "unsupported HCC_TARGET: $target" ;;
esac

[ -d "$src_dir" ] || die "missing patched TinyCC source: $src_dir"
[ -x "$hcc_dir/bin/hcpp" ] || die "missing hcpp under $hcc_dir/bin"
[ -x "$hcc_dir/bin/hcc1" ] || die "missing hcc1 under $hcc_dir/bin"
[ -x "$hcc_dir/bin/hcc-m1" ] || die "missing hcc-m1 under $hcc_dir/bin"
[ -d "$mes_libc/include" ] || die "missing Mes libc include directory: $mes_libc/include"
[ -f "$mes_libc/lib/libc.c" ] || die "missing Mes libc aggregate: $mes_libc/lib/libc.c"
[ -d "$m2libc/$m2_arch" ] || die "missing M2libc $m2_arch directory: $m2libc"

bin_dir=$out_dir/bin
lib_dir=$out_dir/lib
include_dir=$out_dir/include
artifact_dir=$out_dir/artifact
rm -rf "$artifact_dir"
mkdir -p "$bin_dir" "$lib_dir" "$include_dir" "$artifact_dir"
cp -R "$src_dir/." "$artifact_dir/"
chmod -R u+w "$artifact_dir"

PATH=$hcc_dir/bin:$PATH
export PATH
ulimit -s unlimited 2>/dev/null || ulimit -s 65532 2>/dev/null || :

compile_m1() {
  input=$1
  output=$2
  base=${output%.M1}
  msg "hcc1 --m1-ir $input"
  hcc1 --target "$hcc_target" --m1-ir -o "$base.hccir" "$input"
  msg "hcc-m1 $base.hccir"
  hcc-m1 --target "$hcc_target" "$base.hccir" "$output"
}

make_ar() {
  tool=$1
  shift
  archive=$1
  shift
  [ ! -e "$archive" ] || rm "$archive"
  "$tool" -ar cr "$archive" "$@"
}

build_libs() {
  tool=$1
  dest=$2
  mkdir -p "$dest"
  for obj in crt1 crti crtn; do
    "$tool" -c -std=c11 -I include -I "$mes_libc/include" -o "$dest/$obj.o" "$mes_libc/lib/$obj.c"
  done
  "$tool" -c -std=c11 -I include -I "$mes_libc/include" -o "$dest/libc.o" "$mes_libc/lib/libc.c"
  "$tool" -c -std=c11 -I include -I "$mes_libc/include" -o "$dest/libgetopt.o" "$mes_libc/lib/libgetopt.c"
  "$tool" -c -I include -I "$mes_libc/include" -D TCC_TARGET_X86_64=1 -o "$dest/libtcc1.o" lib/libtcc1.c
  make_ar "$tool" "$dest/libc.a" "$dest/libc.o"
  make_ar "$tool" "$dest/libgetopt.a" "$dest/libgetopt.o"
  make_ar "$tool" "$dest/libtcc1.a" "$dest/libtcc1.o"
}

tcc_defs() {
  sysinclude=$1
  cat <<EOF
-D__linux__=1
-DBOOTSTRAP=1
-DHAVE_LONG_LONG=1
-DHAVE_SETJMP=1
-DHAVE_BITFIELD=1
-DHAVE_FLOAT=1
-D$tcc_target_define=1
-Dinline=
-DCONFIG_TCCDIR=\\"\\"
-DCONFIG_SYSROOT=\\"\\"
-DCONFIG_TCC_CRTPREFIX=\\"{B}\\"
-DCONFIG_TCC_ELFINTERP=\\"/mes/loader\\"
-DCONFIG_TCC_LIBPATHS=\\"{B}\\"
-DCONFIG_TCC_SYSINCLUDEPATHS=\\"$sysinclude\\"
-DTCC_LIBGCC=\\"libc.a\\"
-DTCC_LIBTCC1=\\"libtcc1.a\\"
-DCONFIG_TCC_LIBTCC1_MES=0
-DCONFIG_TCCBOOT=1
-DCONFIG_TCC_STATIC=1
-DCONFIG_USE_LIBGCC=1
-DTCC_MES_LIBC=1
-DTCC_VERSION=\\"0.9.28-unstable-2024-07-07\\"
-DONE_SOURCE=1
-DCONFIG_TCC_SEMLOCK=0
EOF
}

(
  cd "$artifact_dir"
  tcc_include_src=$PWD/include
  tcc_sysinclude_path=$include_dir

  cat > config.h <<EOF
#define BOOTSTRAP 1
#define HAVE_LONG_LONG 1
#define HAVE_SETJMP 1
#define HAVE_BITFIELD 1
#define HAVE_FLOAT 1
#define $tcc_target_define 1
#define inline
#define CONFIG_TCCDIR ""
#define CONFIG_SYSROOT ""
#define CONFIG_TCC_CRTPREFIX "{B}"
#define CONFIG_TCC_ELFINTERP "/mes/loader"
#define CONFIG_TCC_LIBPATHS "{B}"
#define CONFIG_TCC_SYSINCLUDEPATHS "$tcc_sysinclude_path"
#define TCC_LIBGCC "libc.a"
#define TCC_LIBTCC1 "libtcc1.a"
#define CONFIG_TCC_LIBTCC1_MES 0
#define CONFIG_TCCBOOT 1
#define CONFIG_TCC_STATIC 1
#define CONFIG_USE_LIBGCC 1
#define TCC_MES_LIBC 1
#define TCC_VERSION "0.9.28-unstable-2024-07-07"
#define ONE_SOURCE 1
#define CONFIG_TCC_SEMLOCK 0
EOF

  msg "hcpp tcc.c"
  hcpp -I . -I "$tcc_include_src" -I "$mes_libc/include" -D__linux__=1 tcc.c > tcc-expanded.c
  hcpp "$support_dir/tcc-bootstrap-support.c" > tcc-bootstrap-support.i
  compile_m1 tcc-bootstrap-support.i tcc-bootstrap-support.M1
  hcpp "$support_dir/tcc-final-overrides.c" > tcc-final-overrides.i
  compile_m1 tcc-final-overrides.i tcc-final-overrides.M1
  compile_m1 tcc-expanded.c tcc.M1

  set -- -f "$m2libc/$m2_arch/$m2_defs"
  [ -z "$support_compat" ] || set -- "$@" -f "$support_dir/$support_compat"
  set -- "$@" \
    -f "$support_dir/$support_start" \
    -f "$support_dir/$support_memory" \
    -f tcc-bootstrap-support.M1 \
    -f tcc.M1 \
    -f tcc-final-overrides.M1 \
    -f "$support_dir/$support_syscalls"
  M1 --architecture "$m1_arch" --little-endian "$@" --output tcc.hex2

  printf ':ELF_end\n' > tcc-end.hex2
  hex2 --architecture "$m1_arch" --little-endian --base-address "$base_address" \
    --file "$m2libc/$m2_arch/$m2_elf" \
    --file tcc.hex2 \
    --file tcc-end.hex2 \
    --output tcc
  chmod 555 tcc

  cp tcc "$bin_dir/tcc-hcc-stage1"
  if [ "$selfhost" != 1 ]; then
    cp tcc "$bin_dir/tcc"
  else
  build_libs ./tcc bootstrap-libs

  ./tcc -B bootstrap-libs -I . -I include -I "$mes_libc/include" $(tcc_defs "$include_dir") tcc.c -o tcc-stage2
  ./tcc-stage2 -B bootstrap-libs -I . -I include -I "$mes_libc/include" $(tcc_defs "$include_dir") tcc.c -o tcc-stage3
  build_libs ./tcc-stage3 final-libs

  cp tcc-stage2 "$bin_dir/tcc-stage2"
  cp tcc-stage3 "$bin_dir/tcc"
  cp final-libs/crt1.o final-libs/crti.o final-libs/crtn.o "$lib_dir/"
  cp final-libs/libc.a final-libs/libgetopt.a final-libs/libtcc1.a "$lib_dir/"
  cp -R "$mes_libc/include/." "$include_dir/"
  chmod -R u+w "$include_dir"
  cp -R include/. "$include_dir/"
  fi
)

chmod 555 "$bin_dir/tcc-hcc-stage1" "$bin_dir/tcc"
[ "$selfhost" != 1 ] || chmod 555 "$bin_dir/tcc-stage2"
msg "TinyCC bootstrap complete: $bin_dir/tcc"
