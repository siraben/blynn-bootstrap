#!/usr/bin/env bash
# Builds upstream blynn/compiler's party→precisely chain on top of orians'
# methodically. Inputs: $METHODICALLY (path to orians' methodically binary),
# $UPSTREAM_DIR (path to ./vendor/blynn-compiler/upstream). Outputs go to
# the current working directory: party.c party multiparty.c multiparty
# party1.c party1 party2.c party2 crossly_up.c crossly_up
# crossly1.c crossly1 precisely_up.c precisely_up.

set -euo pipefail

: "${METHODICALLY:?set METHODICALLY=path/to/methodically}"
: "${UPSTREAM_DIR:?set UPSTREAM_DIR=path/to/upstream}"
: "${M2_ARCH:=amd64}"
: "${M2_OS:=Linux}"
: "${PRECISELY_TOP:=33554432}"

INN="$UPSTREAM_DIR/inn"

step() { printf '\n=== %s ===\n' "$*"; }

compile_m2() {
  local src=$1; local out=$2; shift 2
  M2-Mesoplanet --operating-system "$M2_OS" --architecture "$M2_ARCH" \
    -f "$src" "$@" -o "$out"
  chmod 555 "$out"
}

# Stage 0: methodically(party.hs) -> party.c. The resulting `party` binary
# still has methodically's argc==3 file-opening main, but upstream party's
# FFI shims read stdin and write stdout. We therefore pass dummy argv paths
# when running only this first binary, and drive its real IO with redirection.
step "methodically -> party.c"
"$METHODICALLY" "$UPSTREAM_DIR/party.hs" party.c

step "M2-Mesoplanet party.c (linking upstream shims)"
compile_m2 party.c party -f "$UPSTREAM_DIR/party_shims.c"

# Helper: cat a list of inn/ modules + a leaf source, pipe through prev,
# emit next stage's .c, then compile it with minimal-bootstrap's M2 path.
# Module list is space-separated names from $INN/<name>.hs; leaf is also
# $INN/<leaf>.hs.
party_step() {
  local out=$1; local prev=$2; local leaf=$3; shift 3
  local files=()
  for m in "$@"; do files+=("$INN/$m.hs"); done
  files+=("$INN/$leaf.hs")
  local input="$out.input.hs"
  step "$prev -> $out.c"
  cat "${files[@]}" > "$input"
  if [ "$prev" = party ]; then
    "./$prev" /dev/null /dev/null < "$input" > "$out.c"
  else
    "./$prev" < "$input" > "$out.c"
  fi
  if [ "$out" = precisely_up ]; then
    sed -i -E "s/enum\\{TOP=[0-9]+\\};/enum{TOP=$PRECISELY_TOP};/" "$out.c"
  fi
  step "M2-Mesoplanet $out.c"
  compile_m2 "$out.c" "$out"
}

party_step multiparty  party       party  Base0 System Ast  Map  Parser  Kiselyov Unify  RTS  Typer
party_step party1      multiparty  party  Base0 System Ast1 Map  Parser1 Kiselyov Unify1 RTS  Typer1
party_step party2      party1      party1 Base1 System Ast2 Map  Parser2 Kiselyov Unify1 RTS1 Typer2
party_step crossly_up  party2      party2 Base1 System Ast3 Map  Parser3 Kiselyov Unify1 RTS2 Typer3
party_step crossly1    crossly_up  precisely Base2          System AstPrecisely Map1 ParserPrecisely KiselyovPrecisely Unify1 RTSPrecisely TyperPrecisely Obj Charser
party_step precisely_up crossly1   precisely BasePrecisely  System AstPrecisely Map1 ParserPrecisely KiselyovPrecisely Unify1 RTSPrecisely TyperPrecisely Obj Charser

step "done"
ls -la party party1 party2 multiparty crossly_up crossly1 precisely_up
