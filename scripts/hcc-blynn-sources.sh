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
hcc_common_modules=${HCC_COMMON_MODULES:-$hcc_dir/hcc-common.modules}

hcc_dir=$(abspath "$hcc_dir")
blynn_dir=$(abspath "$blynn_dir")
out_dir=$(abspath "$out_dir")

[ -d "$hcc_dir/src" ] || die "missing HCC source directory: $hcc_dir"
[ -d "$blynn_dir/inn" ] || die "missing Blynn inn directory: $blynn_dir/inn"
[ -f "$hcpp_modules" ] || die "missing hcpp module manifest: $hcpp_modules"
[ -f "$hcc1_modules" ] || die "missing hcc1 module manifest: $hcc1_modules"
[ -f "$hcc_common_modules" ] || die "missing common module manifest: $hcc_common_modules"

mkdir -p "$out_dir"

assemble() {
  _manifest=$1
  _out=$2

  : > "$_out"
  while IFS= read -r _as_entry || [ -n "$_as_entry" ]; do
    case $_as_entry in
      "" | "#"*) continue ;;
      blynn:*) src=$blynn_dir/${_as_entry#blynn:} ;;
      hcc:*) src=$hcc_dir/${_as_entry#hcc:} ;;
      *) die "bad module manifest entry in $_manifest: $_as_entry" ;;
    esac
    [ -f "$src" ] || die "missing module source: $src"
    append_file "$src" "$_out"
  done < "$_manifest"
}

manifest_has_entry() {
  _needle=$1
  _manifest=$2

  while IFS= read -r _mhe_entry || [ -n "$_mhe_entry" ]; do
    case $_mhe_entry in
      "" | "#"*) continue ;;
    esac
    [ "$_mhe_entry" = "$_needle" ] && return 0
  done < "$_manifest"
  return 1
}

assemble_except() {
  _manifest=$1
  _skip_manifest=$2
  _out=$3

  : > "$_out"
  while IFS= read -r _ae_entry || [ -n "$_ae_entry" ]; do
    case $_ae_entry in
      "" | "#"*) continue ;;
    esac
    if manifest_has_entry "$_ae_entry" "$_skip_manifest"; then
      continue
    fi
    case $_ae_entry in
      blynn:*) src=$blynn_dir/${_ae_entry#blynn:} ;;
      hcc:*) src=$hcc_dir/${_ae_entry#hcc:} ;;
      *) die "bad module manifest entry in $_manifest: $_ae_entry" ;;
    esac
    [ -f "$src" ] || die "missing module source: $src"
    append_file "$src" "$_out"
  done < "$_manifest"
}

msg "concatenate common HCC Haskell sources"
assemble "$hcc_common_modules" "$out_dir/hcc-common-full.hs"

msg "concatenate hcpp Haskell sources"
assemble "$hcpp_modules" "$out_dir/hcpp-full.hs"
assemble_except "$hcpp_modules" "$hcc_common_modules" "$out_dir/hcpp-tail.hs"

msg "concatenate hcc1 Haskell sources"
assemble "$hcc1_modules" "$out_dir/hcc1-full.hs"
assemble_except "$hcc1_modules" "$hcc_common_modules" "$out_dir/hcc1-tail.hs"

msg "HCC Blynn sources written to $out_dir"
