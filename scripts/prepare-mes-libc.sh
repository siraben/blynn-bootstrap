#!/usr/bin/env sh

set -eu

case $0 in
  */*) script_path=$0 ;;
  *) script_path=$(command -v "$0") || exit 1 ;;
esac
script_dir=${script_path%/*}
[ "$script_dir" = "$script_path" ] && script_dir=.
script_dir=$(CDPATH= cd "$script_dir" && pwd)
. "${BOOTSTRAP_LIB:-$script_dir/lib/bootstrap.sh}"
repo_dir=$(repo_root_from_script_dir "$script_dir")

require_cmd cp
require_cmd mkdir
require_cmd rm
require_cmd mv

src_dir=${GNU_MES_DIR:-${1:-build/upstreams/gnu-mes}}
out_dir=${OUT_DIR:-${2:-build/mes-libc}}
# This is the Mes source/header view, not the HCC emission target.
arch=${MES_LIBC_ARCH:-x86_64}
case $arch in
  x86_64) ;;
  x86 | i686 | i386) die "unsupported MES_LIBC_ARCH: $arch (Mes replacements require LP64 and x86_64 setjmp)" ;;
  *) die "unsupported MES_LIBC_ARCH: $arch (use x86_64; AArch64 callers also use this header view)" ;;
esac
strtod=${MES_STRTOD_SOURCE:-$repo_dir/nix/sources/mes-libc/strtod.c}
ldexp=${MES_LDEXP_SOURCE:-$repo_dir/nix/sources/mes-libc/ldexp-ldexpl.c}
setjmp=${MES_SETJMP_SOURCE:-$repo_dir/nix/sources/mes-libc/x86_64-setjmp.c}
config_h=${MES_CONFIG_SOURCE:-$repo_dir/nix/sources/mes-libc/config.h}

src_dir=$(abspath "$src_dir")
out_dir=$(abspath "$out_dir")

[ -d "$src_dir" ] || die "missing patched GNU Mes source: $src_dir"
[ -f "$strtod" ] || die "missing strtod source: $strtod"
[ -f "$ldexp" ] || die "missing ldexp source: $ldexp"
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

(
  cd "$out_dir"
  . ./build-aux/configure-lib.sh
  inserted=0
  aggregate="$out_dir/lib/libc.c.tmp"
  trap 'rm -f "$aggregate"' EXIT HUP INT TERM
  : > "$aggregate"
  for rel in $libc_gnu_SOURCES; do
    case $rel in
      lib/mes/abtod.c | lib/stdlib/strtod.c | lib/stdlib/strtof.c | lib/stdlib/strtold.c | lib/stub/ldexp.c)
        continue
        ;;
    esac
    # Pinned Mes put uname.c at surviving entry 101; keep that exact boundary.
    if [ "$rel" = lib/linux/uname.c ]; then
      [ "$inserted" -eq 0 ] || die "repeated Mes libc insertion anchor: lib/linux/uname.c"
      append_file "$strtod" "$aggregate"
      append_file "$ldexp" "$aggregate"
      inserted=1
    fi
    append_file "$out_dir/$rel" "$aggregate"
  done
  [ "$inserted" -eq 1 ] || die "missing Mes libc insertion anchor: lib/linux/uname.c"
  mv "$aggregate" "$out_dir/lib/libc.c"
)

cp "$out_dir/lib/linux/$arch-mes-gcc/crt1.c" "$out_dir/lib/crt1.c"
cp "$out_dir/lib/linux/$arch-mes-gcc/crti.c" "$out_dir/lib/crti.c"
cp "$out_dir/lib/linux/$arch-mes-gcc/crtn.c" "$out_dir/lib/crtn.c"
cp "$out_dir/lib/posix/getopt.c" "$out_dir/lib/libgetopt.c"

msg "Mes libc view written to $out_dir"
