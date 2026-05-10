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

require_cmd mkdir

hcc_dir=${HCC_DIR:-${1:-hcc}}
blynn_dir=${BLYNN_DIR:-${2:-build/upstreams/blynn-compiler}}
out_dir=${OUT_DIR:-${3:-build/hcc-blynn-sources}}
hcpp_modules=${HCPP_MODULES:-$hcc_dir/hcpp.modules}
hcc1_modules=${HCC1_MODULES:-$hcc_dir/hcc1.modules}

hcc_dir=$(abspath "$hcc_dir")
blynn_dir=$(abspath "$blynn_dir")
out_dir=$(abspath "$out_dir")

[ -d "$hcc_dir/src" ] || die "missing HCC source directory: $hcc_dir"
[ -d "$blynn_dir/inn" ] || die "missing Blynn inn directory: $blynn_dir/inn"
[ -f "$hcpp_modules" ] || die "missing hcpp module manifest: $hcpp_modules"
[ -f "$hcc1_modules" ] || die "missing hcc1 module manifest: $hcc1_modules"

mkdir -p "$out_dir"

assemble() {
  manifest=$1
  out=$2

  : > "$out"
  while IFS= read -r entry || [ -n "$entry" ]; do
    case $entry in
      "" | "#"*) continue ;;
      blynn:*) src=$blynn_dir/${entry#blynn:} ;;
      hcc:*) src=$hcc_dir/${entry#hcc:} ;;
      *) die "bad module manifest entry in $manifest: $entry" ;;
    esac
    [ -f "$src" ] || die "missing module source: $src"
    append_file "$src" "$out"
  done < "$manifest"
}

msg "concatenate hcpp Haskell sources"
assemble "$hcpp_modules" "$out_dir/hcpp-full.hs"

msg "concatenate hcc1 Haskell sources"
assemble "$hcc1_modules" "$out_dir/hcc1-full.hs"

msg "HCC Blynn sources written to $out_dir"
