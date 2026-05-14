#!/bin/sh

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

require_cmd cp
require_cmd mkdir

source_dir=${HCC_BLYNN_SOURCES_DIR:-${1:-build/hcc-blynn-sources}}
out_dir=${OUT_DIR:-${2:-build/hcc-blynn-c}}
precisely_up=${PRECISELY_UP:-precisely_up}
objects_dir=${HCC_BLYNN_OBJECTS_DIR:-${3:-}}

source_dir=$(abspath "$source_dir")
out_dir=$(abspath "$out_dir")
[ -n "$objects_dir" ] || die "missing HCC_BLYNN_OBJECTS_DIR or third argument"
objects_dir=$(abspath "$objects_dir")

[ -f "$source_dir/hcpp-full.hs" ] || die "missing hcpp-full.hs in $source_dir"
[ -f "$source_dir/hcc1-full.hs" ] || die "missing hcc1-full.hs in $source_dir"
[ -f "$source_dir/hcpp-tail.hs" ] || die "missing hcpp-tail.hs in $source_dir"
[ -f "$source_dir/hcc1-tail.hs" ] || die "missing hcc1-tail.hs in $source_dir"
require_cmd "$precisely_up"
[ -f "$objects_dir/common-object-input.hs" ] || die "missing common-object-input.hs in $objects_dir"

mkdir -p "$out_dir"
cp "$source_dir/hcpp-full.hs" "$out_dir/hcpp-full.hs"
cp "$source_dir/hcc1-full.hs" "$out_dir/hcc1-full.hs"
cp "$source_dir/hcpp-tail.hs" "$out_dir/hcpp-tail.hs"
cp "$source_dir/hcc1-tail.hs" "$out_dir/hcc1-tail.hs"

compile_with_common_objects() {
  name=$1
  tail=$2
  output=$3

  object_input=$out_dir/$name-object-input.hs

  : > "$object_input"
  append_file "$objects_dir/common-object-input.hs" "$object_input"
  append_file "$tail" "$object_input"

  msg "precisely_up $name common object IR + source -> ${output##*/}"
  "$precisely_up" < "$object_input" > "$output"
}

compile_with_common_objects hcpp "$out_dir/hcpp-tail.hs" "$out_dir/hcpp-blynn.c"
compile_with_common_objects hcc1 "$out_dir/hcc1-tail.hs" "$out_dir/hcc1-blynn.c"

msg "HCC Blynn C written to $out_dir"
