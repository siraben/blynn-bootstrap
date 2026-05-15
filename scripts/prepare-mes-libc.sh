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

require_cmd cp
require_cmd mkdir
require_cmd rm

src_dir=${GNU_MES_DIR:-${1:-build/upstreams/gnu-mes}}
out_dir=${OUT_DIR:-${2:-build/mes-libc}}
arch=${MES_LIBC_ARCH:-x86_64}
setjmp=${MES_SETJMP_SOURCE:-$repo_dir/nix/sources/mes-libc/x86_64-setjmp.c}
config_h=${MES_CONFIG_SOURCE:-$repo_dir/nix/sources/mes-libc/config.h}

src_dir=$(abspath "$src_dir")
out_dir=$(abspath "$out_dir")

[ -d "$src_dir" ] || die "missing patched GNU Mes source: $src_dir"
[ -f "$setjmp" ] || die "missing setjmp source: $setjmp"
[ -f "$config_h" ] || die "missing Mes config header: $config_h"

rm -rf "$out_dir"
mkdir -p "$out_dir"
cp -R "$src_dir/." "$out_dir/"
chmod -R u+w "$out_dir"

mkdir -p "$out_dir/include/arch" "$out_dir/include/mes" "$out_dir/lib"
cp "$out_dir/include/linux/$arch/kernel-stat.h" "$out_dir/include/arch/kernel-stat.h"
cp "$out_dir/include/linux/$arch/signal.h" "$out_dir/include/arch/signal.h"
cp "$out_dir/include/linux/$arch/syscall.h" "$out_dir/include/arch/syscall.h"
cp "$config_h" "$out_dir/include/mes/config.h"
cp "$setjmp" "$out_dir/lib/$arch-mes-gcc/setjmp.c"

msg "assemble GNU Mes libc source order"
cat > "$out_dir/config.sh" <<EOF
compiler=gcc
mes_bits=64
mes_cpu=$arch
mes_kernel=linux
mes_libc=mes
mes_system=$arch-linux
EOF

: > "$out_dir/lib/libc.c"
(
  cd "$out_dir"
  . ./build-aux/configure-lib.sh
  for rel in $libc_gnu_SOURCES; do
    append_file "$out_dir/$rel" "$out_dir/lib/libc.c"
  done
)

cp "$out_dir/lib/linux/$arch-mes-gcc/crt1.c" "$out_dir/lib/crt1.c"
cp "$out_dir/lib/linux/$arch-mes-gcc/crti.c" "$out_dir/lib/crti.c"
cp "$out_dir/lib/linux/$arch-mes-gcc/crtn.c" "$out_dir/lib/crtn.c"
cp "$out_dir/lib/posix/getopt.c" "$out_dir/lib/libgetopt.c"

msg "Mes libc view written to $out_dir"
