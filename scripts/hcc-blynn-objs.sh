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
require_cmd rm

source_dir=${HCC_BLYNN_SOURCES_DIR:-${1:-build/hcc-blynn-sources}}
out_dir=${OUT_DIR:-${2:-build/hcc-blynn-objs}}
precisely_up=${PRECISELY_UP:-precisely_up}

source_dir=$(abspath "$source_dir")
out_dir=$(abspath "$out_dir")

[ -f "$source_dir/hcc-common-full.hs" ] || die "missing hcc-common-full.hs in $source_dir"
require_cmd "$precisely_up"

materialize_object_script() {
  _script=$1
  _dir=$2

  while IFS= read -r _line || [ -n "$_line" ]; do
    case $_line in
      "cat > "*.ob" << EOF")
        _rest=${_line#cat > }
        _file=${_rest% << EOF}
        : > "$_dir/$_file"
        while IFS= read -r _obj_line || [ -n "$_obj_line" ]; do
          [ "$_obj_line" = EOF ] && break
          printf '%s\n' "$_obj_line" >> "$_dir/$_file"
        done
        ;;
      "")
        ;;
      *)
        die "unexpected object script line: $_line"
        ;;
    esac
  done < "$_script"
}

mkdir -p "$out_dir/common-objects"
cp "$source_dir/hcc-common-full.hs" "$out_dir/hcc-common-full.hs"
for obj in "$out_dir/common-objects"/*.ob; do
  [ -f "$obj" ] && rm "$obj"
done
[ -f "$out_dir/common-objects.sh" ] && rm "$out_dir/common-objects.sh"
[ -f "$out_dir/common-object-input.hs" ] && rm "$out_dir/common-object-input.hs"

msg "precisely_up hcc common source -> object IR"
"$precisely_up" obj < "$out_dir/hcc-common-full.hs" > "$out_dir/common-objects.sh"
materialize_object_script "$out_dir/common-objects.sh" "$out_dir/common-objects"

: > "$out_dir/common-object-input.hs"
for obj in "$out_dir/common-objects"/*.ob; do
  case ${obj##*/} in
    prim.ob)
      # The primitive module is injected automatically when absent. Its
      # serialized spelling uses module '#', which the surface parser rejects.
      continue
      ;;
  esac
  append_file "$obj" "$out_dir/common-object-input.hs"
done

msg "HCC common Blynn objects written to $out_dir"
