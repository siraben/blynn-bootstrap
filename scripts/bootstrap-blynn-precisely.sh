#!/bin/sh

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
require_cmd mkdir
require_cmd mv
require_cmd sed
require_cmd M2-Mesoplanet

src_dir=${BLYNN_DIR:-${1:-build/upstreams/blynn-compiler}}
out_dir=${OUT_DIR:-build/blynn-precisely}
methodically=${METHODICALLY:-build/blynn-root/bin/methodically}

src_dir=$(abspath "$src_dir")
out_dir=$(abspath "$out_dir")
methodically=$(abspath "$methodically")
bin_dir=$out_dir/bin
gen_dir=$out_dir/generated
inn_dir=$src_dir/inn

[ -d "$src_dir" ] || die "missing Blynn compiler source: $src_dir"
[ -x "$methodically" ] || die "missing methodically binary: $methodically"

mkdir -p "$bin_dir" "$gen_dir"

party_step() {
  out=$1
  prev=$2
  leaf=$3
  shift 3
  input=$gen_dir/$out.input.hs

  : > "$input"
  for module in "$@"; do
    append_file "$inn_dir/$module.hs" "$input"
  done
  append_file "$inn_dir/$leaf.hs" "$input"

  msg "$prev -> $out.c"
  if [ "$prev" = party ]; then
    "$bin_dir/$prev" /dev/null /dev/null < "$input" > "$gen_dir/$out.c"
  else
    "$bin_dir/$prev" < "$input" > "$gen_dir/$out.c"
  fi
  if [ "$out" = precisely_up ]; then
    tmp=$gen_dir/$out.c.tmp
    sed "s/enum{TOP=[0-9][0-9]*};/enum{TOP=${PRECISELY_TOP:-33554432}};/" "$gen_dir/$out.c" > "$tmp"
    mv "$tmp" "$gen_dir/$out.c"
  fi
  compile_m2 "$gen_dir/$out.c" "$bin_dir/$out"
}

msg "methodically -> party.c"
"$methodically" "$src_dir/party.hs" "$gen_dir/party.c"
compile_m2 "$gen_dir/party.c" "$bin_dir/party" -f "$src_dir/party_shims.c"

party_step multiparty party party Base0 System Ast Map Parser Kiselyov Unify RTS Typer
party_step party1 multiparty party Base0 System Ast1 Map Parser1 Kiselyov Unify1 RTS Typer1
party_step party2 party1 party1 Base1 System Ast2 Map Parser2 Kiselyov Unify1 RTS1 Typer2
party_step crossly_up party2 party2 Base1 System Ast3 Map Parser3 Kiselyov Unify1 RTS2 Typer3
party_step crossly1 crossly_up precisely Base2 System AstPrecisely Map1 ParserPrecisely KiselyovPrecisely Unify1 RTSPrecisely TyperPrecisely Obj Charser
party_step precisely_up crossly1 precisely BasePrecisely System AstPrecisely Map1 ParserPrecisely KiselyovPrecisely Unify1 RTSPrecisely TyperPrecisely Obj Charser

msg "precisely chain complete: $bin_dir/precisely_up"
