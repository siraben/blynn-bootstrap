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

source_dir=$(abspath "$source_dir")
out_dir=$(abspath "$out_dir")

[ -f "$source_dir/hcpp-full.hs" ] || die "missing hcpp-full.hs in $source_dir"
[ -f "$source_dir/hcc1-full.hs" ] || die "missing hcc1-full.hs in $source_dir"
require_cmd "$precisely_up"

mkdir -p "$out_dir"
cp "$source_dir/hcpp-full.hs" "$out_dir/hcpp-full.hs"
cp "$source_dir/hcc1-full.hs" "$out_dir/hcc1-full.hs"

msg "precisely_up hcpp-full.hs -> hcpp-blynn.c"
"$precisely_up" < "$out_dir/hcpp-full.hs" > "$out_dir/hcpp-blynn.c"

msg "precisely_up hcc1-full.hs -> hcc1-blynn.c"
"$precisely_up" < "$out_dir/hcc1-full.hs" > "$out_dir/hcc1-blynn.c"

msg "HCC Blynn C written to $out_dir"
