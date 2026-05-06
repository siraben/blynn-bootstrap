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
: "${CC:=cc}"
: "${CFLAGS:=-D_GNU_SOURCE -std=c99 -O2}"

INN="$UPSTREAM_DIR/inn"

step() { printf '\n=== %s ===\n' "$*"; }

# Stage 0: methodically(party.hs) -> party.c, then patch open_files() so
# that the resulting `party` binary uses stdin/stdout (upstream's
# Makefile-driven convention) instead of methodically's argc==3 file
# convention. From `party` onward, each generated binary emits its own
# main and we don't need this patch.
step "methodically -> party.c"
"$METHODICALLY" "$UPSTREAM_DIR/party.hs" party.c.raw
perl -0pe 's/void open_files\(\) \{\n(?:.*\n)*?\}\n/void open_files() { input_file = stdin; destination_file = stdout; }\n/' \
  party.c.raw > party.c
rm party.c.raw

step "cc party.c (linking upstream shims)"
$CC $CFLAGS party.c "$UPSTREAM_DIR/party_shims.c" -o party

# Helper: cat a list of inn/ modules + a leaf source, pipe through prev,
# emit next stage's .c, then cc it. Module list is space-separated names
# from $INN/<name>.hs; leaf is also $INN/<leaf>.hs.
party_step() {
  local out=$1; local prev=$2; local leaf=$3; shift 3
  local files=()
  for m in "$@"; do files+=("$INN/$m.hs"); done
  files+=("$INN/$leaf.hs")
  step "$prev -> $out.c"
  cat "${files[@]}" | "./$prev" > "$out.c"
  step "cc $out.c"
  $CC $CFLAGS -lm "$out.c" -o "$out"
}

party_step multiparty  party       party  Base0 System Ast  Map  Parser  Kiselyov Unify  RTS  Typer
party_step party1      multiparty  party  Base0 System Ast1 Map  Parser1 Kiselyov Unify1 RTS  Typer1
party_step party2      party1      party1 Base1 System Ast2 Map  Parser2 Kiselyov Unify1 RTS1 Typer2
party_step crossly_up  party2      party2 Base1 System Ast3 Map  Parser3 Kiselyov Unify1 RTS2 Typer3
party_step crossly1    crossly_up  precisely Base2          System AstPrecisely Map1 ParserPrecisely KiselyovPrecisely Unify1 RTSPrecisely TyperPrecisely Obj Charser
party_step precisely_up crossly1   precisely BasePrecisely  System AstPrecisely Map1 ParserPrecisely KiselyovPrecisely Unify1 RTSPrecisely TyperPrecisely Obj Charser

step "done"
ls -la party party1 party2 multiparty crossly_up crossly1 precisely_up
