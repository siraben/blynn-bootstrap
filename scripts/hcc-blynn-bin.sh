#!/usr/bin/env sh

set -eu

case ${BOOTSTRAP_LIB:-} in
  "")
    case $0 in
      */*) script_path=$0 ;;
      *) script_path=$(command -v "$0") || exit 1 ;;
    esac
    script_dir=${script_path%/*}
    [ "$script_dir" = "$script_path" ] && script_dir=.
    script_dir=$(CDPATH= cd "$script_dir" && pwd)
    . "$script_dir/lib/bootstrap.sh"
    ;;
  *) . "$BOOTSTRAP_LIB" ;;
esac

require_cmd chmod
require_cmd cp
require_cmd mkdir

source_dir=${HCC_BLYNN_C_DIR:-${1:-build/hcc-blynn-c}}
hcc_dir=${HCC_DIR:-${2:-hcc}}
out_dir=${OUT_DIR:-${3:-build/hcc-blynn-bin}}
backend=${HCC_C_BACKEND:-m2}
hcpp_top=${HCPP_TOP:-134217728}
hcc1_top=${HCC1_TOP:-134217728}
host_cc=${HOST_CC:-${CC:-cc}}
host_cflags=${HOST_CFLAGS:--O2}
tcc=${TCC:-tcc}
tcc_flags=${TCC_FLAGS:-}

source_dir=$(abspath "$source_dir")
hcc_dir=$(abspath "$hcc_dir")
out_dir=$(abspath "$out_dir")
bin_dir=$out_dir/bin
artifact_dir=$out_dir/artifact

[ -f "$source_dir/hcpp-blynn.c" ] || die "missing hcpp-blynn.c in $source_dir"
[ -f "$source_dir/hcc1-blynn.c" ] || die "missing hcc1-blynn.c in $source_dir"
[ -f "$hcc_dir/cbits/hcc_runtime.c" ] || die "missing HCC runtime under $hcc_dir"
[ -f "$hcc_dir/cbits/hcc_runtime_m2.c" ] || die "missing HCC M2 runtime under $hcc_dir"
[ -f "$hcc_dir/cbits/hcc_m1.c" ] || die "missing hcc-m1 C source under $hcc_dir"
[ -f "$hcc_dir/cbits/hcc_m1_arch_aarch64.c" ] || die "missing hcc-m1 AArch64 source under $hcc_dir"

mkdir -p "$bin_dir" "$artifact_dir/cbits"
cp "$source_dir/hcpp-blynn.c" "$artifact_dir/hcpp-blynn.c"
cp "$source_dir/hcc1-blynn.c" "$artifact_dir/hcc1-blynn.c"
cp "$hcc_dir/cbits/hcc_runtime.c" "$artifact_dir/cbits/hcc_runtime.c"
cp "$hcc_dir/cbits/hcc_runtime_m2.c" "$artifact_dir/cbits/hcc_runtime_m2.c"
cp "$hcc_dir/cbits/hcc_m1.c" "$artifact_dir/cbits/hcc_m1.c"
for arch_source in "$hcc_dir"/cbits/hcc_m1_arch_*.c; do
  [ -f "$arch_source" ] || continue
  cp "$arch_source" "$artifact_dir/cbits/${arch_source##*/}"
done
if [ -n "${M2LIBC_PATH:-}" ]; then
  m2libc=$(abspath "$M2LIBC_PATH")
  mkdir -p "$artifact_dir/M2libc"
  cp "$m2libc/bootstrappable.h" "$artifact_dir/M2libc/bootstrappable.h"
  cp "$m2libc/bootstrappable.c" "$artifact_dir/M2libc/bootstrappable.c"
fi

patch_top() {
  src=$1
  dst=$2
  top=$3
  marker='enum{TOP='
  found=0

  : > "$dst"
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      *"$marker"*"};"*)
        prefix=${line%%"$marker"*}
        rest=${line#*"$marker"}
        suffix=${rest#*"};"}
        printf '%s%s%s\n' "$prefix" "enum{TOP=$top};" "$suffix" >> "$dst"
        found=1
        ;;
      *) printf '%s\n' "$line" >> "$dst" ;;
    esac
  done < "$src"
  [ "$found" = 1 ] || die "TOP definition not found in $src"
}

prepare_m2_source() {
  file=$1
  tmp=$file.body
  cp "$file" "$tmp"
  printf '%s\n' '#define HCC_RTS_USE_EXTERNAL_ALLOC 1' > "$file"
  while IFS= read -r line || [ -n "$line" ]; do
    case $line in
      "static inline u isAddr(u n) { return n>=128; }")
        printf '%s\n' "static inline u isAddr(u n) { return n>=128 && n<TOP; }" >> "$file"
        ;;
      *) printf '%s\n' "$line" >> "$file" ;;
    esac
  done < "$tmp"
  rm "$tmp"
}

(
  cd "$artifact_dir"
  hcpp_c=hcpp-blynn.patched.c
  hcc1_c=hcc1-blynn.patched.c
  patch_top hcpp-blynn.c "$hcpp_c" "$hcpp_top"
  patch_top hcc1-blynn.c "$hcc1_c" "$hcc1_top"

  case $backend in
    m2)
      require_cmd "${M2_MESOPLANET:-M2-Mesoplanet}"
      prepare_m2_source "$hcpp_c"
      prepare_m2_source "$hcc1_c"
      compile_m2 "$hcpp_c" hcpp -f cbits/hcc_runtime_m2.c
      compile_m2 "$hcc1_c" hcc1 -f cbits/hcc_runtime_m2.c
      compile_m2 cbits/hcc_m1.c hcc-m1
      ;;
    gcc | cc | host)
      require_cmd "$host_cc"
      msg "$host_cc $hcpp_c -> hcpp"
      "$host_cc" $host_cflags "$hcpp_c" cbits/hcc_runtime.c -o hcpp
      msg "$host_cc $hcc1_c -> hcc1"
      "$host_cc" $host_cflags "$hcc1_c" cbits/hcc_runtime.c -o hcc1
      msg "$host_cc cbits/hcc_m1.c -> hcc-m1"
      "$host_cc" -O2 cbits/hcc_m1.c -o hcc-m1
      ;;
    tcc)
      require_cmd "$tcc"
      msg "$tcc $hcpp_c -> hcpp"
      "$tcc" $tcc_flags "$hcpp_c" cbits/hcc_runtime.c -o hcpp
      msg "$tcc $hcc1_c -> hcc1"
      "$tcc" $tcc_flags "$hcc1_c" cbits/hcc_runtime.c -o hcc1
      msg "$tcc cbits/hcc_m1.c -> hcc-m1"
      "$tcc" $tcc_flags cbits/hcc_m1.c -o hcc-m1
      ;;
    *) die "unknown HCC_C_BACKEND: $backend" ;;
  esac
)

cp "$artifact_dir/hcpp" "$bin_dir/hcpp"
cp "$artifact_dir/hcc1" "$bin_dir/hcc1"
cp "$artifact_dir/hcc-m1" "$bin_dir/hcc-m1"
chmod 555 "$bin_dir/hcpp" "$bin_dir/hcc1" "$bin_dir/hcc-m1"
msg "HCC binaries written to $bin_dir"
