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

require_cmd chmod
require_cmd cp
require_cmd ln
require_cmd mkdir
require_cmd M2-Mesoplanet
require_cmd rm

src_dir=${ORIANSJ_BLYNN_DIR:-${1:-build/upstreams/oriansj-blynn-compiler}}
out_dir=${OUT_DIR:-build/blynn-root}
m2libc_dir=${M2LIBC_PATH:-$src_dir/M2libc}

src_dir=$(abspath "$src_dir")
out_dir=$(abspath "$out_dir")
m2libc_dir=$(abspath "$m2libc_dir")
bin_dir=$out_dir/bin
gen_dir=$out_dir/generated
share_dir=$out_dir/share/blynn
work_dir=$out_dir/work

[ -d "$src_dir" ] || die "missing OriansJ Blynn source: $src_dir"
[ -d "$m2libc_dir" ] || die "missing M2libc: $m2libc_dir"

mkdir -p "$bin_dir" "$gen_dir" "$share_dir" "$work_dir"

link_source() {
  rm -f "$work_dir/$1"
  ln -s "$src_dir/$1" "$work_dir/$1"
}

link_tree() {
  rm -f "$work_dir/$1"
  ln -s "$src_dir/$1" "$work_dir/$1"
}

link_external_tree() {
  rm -f "$work_dir/$1"
  ln -s "$2" "$work_dir/$1"
}

run_vm_raw() {
  out=$1
  raw=$2
  parser=$3
  level=$4
  "$bin_dir/vm" --raw "$raw" -pb "$parser" -lf "$level" -o "$gen_dir/$out"
}

run_vm_compile() {
  out=$1
  raw=$2
  source=$3
  foreign=${4:-}
  "$bin_dir/vm" -f "$source" $foreign --raw "$raw" --rts_c run -o "$gen_dir/$out"
}

compile_stage_c() {
  name=$1
  prev_bin=$2
  source=$3
  "$bin_dir/$prev_bin" "$source" "$gen_dir/$name.c"
  (
    cd "$work_dir"
    compile_m2 "$gen_dir/$name.c" "$bin_dir/$name"
  )
}

msg "compile pack_blobs"
link_external_tree M2libc "$m2libc_dir"
link_source gcc_req.h
link_source pack_blobs.c
(
  cd "$work_dir"
  compile_m2 pack_blobs.c "$bin_dir/pack_blobs"
)

msg "pack bootstrap blobs"
"$bin_dir/pack_blobs" -f "$src_dir/blob/parenthetically.source" -o "$gen_dir/parenthetically"
"$bin_dir/pack_blobs" -f "$src_dir/blob/exponentially.source" -o "$gen_dir/exponentially"
"$bin_dir/pack_blobs" -f "$src_dir/blob/practically.source" -o "$gen_dir/practically"
"$bin_dir/pack_blobs" -f "$src_dir/blob/singularity.source" -o "$gen_dir/singularity_blob"

msg "compile vm"
link_source vm.c
(
  cd "$work_dir"
  compile_m2 vm.c "$bin_dir/vm"
)

msg "build raw images"
run_vm_raw raw_l "$src_dir/blob/root" bootstrap "$gen_dir/parenthetically"
run_vm_raw raw_m "$gen_dir/raw_l" "$gen_dir/parenthetically" "$gen_dir/exponentially"
run_vm_raw raw_n "$gen_dir/raw_m" "$gen_dir/exponentially" "$gen_dir/practically"
run_vm_raw raw_o "$gen_dir/raw_n" "$gen_dir/practically" "$gen_dir/singularity_blob"
run_vm_raw raw_p "$gen_dir/raw_o" "$gen_dir/singularity_blob" "$src_dir/singularity"
run_vm_raw raw_q "$gen_dir/raw_p" singularity "$src_dir/semantically"
run_vm_raw raw_r "$gen_dir/raw_q" semantically "$src_dir/stringy"
run_vm_raw raw_s "$gen_dir/raw_r" stringy "$src_dir/binary"
run_vm_raw raw_t "$gen_dir/raw_s" binary "$src_dir/algebraically"
run_vm_raw raw_u "$gen_dir/raw_t" algebraically "$src_dir/parity.hs"
run_vm_raw raw_v "$gen_dir/raw_u" parity.hs "$src_dir/fixity.hs"
run_vm_raw raw_w "$gen_dir/raw_v" fixity.hs "$src_dir/typically.hs"
run_vm_raw raw_x "$gen_dir/raw_w" typically.hs "$src_dir/classy.hs"
run_vm_raw raw_y "$gen_dir/raw_x" classy.hs "$src_dir/barely.hs"
run_vm_raw raw_z "$gen_dir/raw_y" barely.hs "$src_dir/barely.hs"

"$bin_dir/vm" -l "$gen_dir/raw_z" -lf "$src_dir/barely.hs" -o "$share_dir/raw"
"$bin_dir/vm" -l "$share_dir/raw" -lf "$src_dir/effectively.hs" --redo -lf "$src_dir/lonely.hs" -o "$gen_dir/lonely_raw.txt"

run_vm_compile patty_raw.txt "$gen_dir/lonely_raw.txt" "$src_dir/patty.hs"
run_vm_compile guardedly_raw.txt "$gen_dir/patty_raw.txt" "$src_dir/guardedly.hs"
run_vm_compile assembly_raw.txt "$gen_dir/guardedly_raw.txt" "$src_dir/assembly.hs"
run_vm_compile mutually_raw.txt "$gen_dir/assembly_raw.txt" "$src_dir/mutually.hs" "--foreign 2"
run_vm_compile uniquely_raw.txt "$gen_dir/mutually_raw.txt" "$src_dir/uniquely.hs" "--foreign 2"
run_vm_compile virtually_raw.txt "$gen_dir/uniquely_raw.txt" "$src_dir/virtually.hs" "--foreign 2"

msg "compile native compiler stages"
"$bin_dir/vm" -f "$src_dir/marginally.hs" --foreign 2 --raw "$gen_dir/virtually_raw.txt" --rts_c run -o "$gen_dir/marginally.c"
(
  cd "$work_dir"
  compile_m2 "$gen_dir/marginally.c" "$bin_dir/marginally"
)
compile_stage_c methodically marginally "$src_dir/methodically.hs"
compile_stage_c crossly methodically "$src_dir/crossly.hs"
compile_stage_c precisely crossly "$src_dir/precisely.hs"

cp "$gen_dir"/*_raw.txt "$share_dir/" 2>/dev/null || true
msg "root chain complete: $bin_dir"
