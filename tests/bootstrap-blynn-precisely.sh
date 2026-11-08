#!/usr/bin/env sh
set -eu

repo_dir=${1:-$(CDPATH= cd "$(dirname "$0")/.." && pwd)}
repo_dir=$(CDPATH= cd "$repo_dir" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
shell=$(command -v sh)

mkdir -p "$work/path" "$work/src/inn" "$work/sources"
# Exercise stage selection and TOP checks without a host compiler or downloads.
for module in Base0 System Ast Map Parser Kiselyov Unify RTS Typer party \
  Ast1 Parser1 Unify1 Typer1 Base1 Ast2 Parser2 RTS1 Typer2 party1 \
  Ast3 Parser3 RTS2 Typer3 party2 Base2 AstPrecisely Map1 ParserPrecisely \
  KiselyovPrecisely RTSPrecisely TyperPrecisely Obj Charser precisely BasePrecisely; do
  printf '%s\n' "$module" > "$work/src/inn/$module.hs"
done
: > "$work/src/party.hs"
: > "$work/src/party_shims.c"
cat > "$work/compiler" <<'EOF'
#!/bin/sh
set -eu
case ${1:-} in
  top)
    cat >/dev/null
    printf 'typedef unsigned u;\nenum{TOP=%s};\n' "${BAD_TOP:-$2}"
    ;;
  obj) cat ;;
  *) cat >/dev/null; printf 'generated C\n' ;;
esac
EOF
cat > "$work/path/M2-Mesoplanet" <<'EOF'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
  case $1 in -o) output=$2; shift ;; esac
  shift
done
[ "${output##*/}" != "${FAIL_STAGE:-}" ] || exit 23
rm -f "$output"
cp "$FAKE_COMPILER" "$output"
EOF
cat > "$work/methodically" <<'EOF'
#!/bin/sh
printf 'party C\n' > "$2"
EOF
chmod +x "$work/compiler" "$work/methodically" "$work/path/M2-Mesoplanet"
export FAKE_COMPILER=$work/compiler
export PATH=$work/path:$PATH

run() {
  env BLYNN_DIR="$work/src" METHODICALLY="$work/methodically" \
    OUT_DIR="$work/out" CROSSLY_TOP=4096 PRECISELY_TOP=2048 \
    "$@" "$shell" "$repo_dir/scripts/bootstrap-blynn-precisely.sh"
}
reject() {
  expected=$1
  shift
  if run "$@" > "$work/rejected.log" 2>&1; then
    echo "unexpected ladder success: $*" >&2
    exit 1
  fi
  grep -F "$expected" "$work/rejected.log"
}

unset BUILD_PRECISELY_UP BLYNN_COMPILER PRECISELY_UP
run FAIL_STAGE=precisely_up
[ -x "$work/out/bin/crossly1" ]
[ ! -e "$work/out/bin/precisely_up" ]
grep -Fx 'enum{TOP=4096};' "$work/out/generated/crossly1.c"
# The default standalone HCC stages must work with only crossly1 on PATH.
export PATH=$work/out/bin:$PATH
for source in hcc-common-full hcpp-full hcc1-full hcpp-tail hcc1-tail; do
  printf '%s\n' "$source" > "$work/sources/$source.hs"
done
cat > "$work/path/materialize-object-script" <<'EOF'
#!/bin/sh
cp "$1" "$2/common.ob"
EOF
chmod +x "$work/path/materialize-object-script"
HCC_BLYNN_SOURCES_DIR=$work/sources OUT_DIR=$work/objs \
  "$shell" "$repo_dir/scripts/hcc-blynn-objs.sh"
HCC_BLYNN_SOURCES_DIR=$work/sources HCC_BLYNN_OBJECTS_DIR=$work/objs \
  HCPP_TOP=4096 HCC1_TOP=2048 OUT_DIR=$work/c \
  "$shell" "$repo_dir/scripts/hcc-blynn-c.sh"
grep -Fx 'enum{TOP=4096};' "$work/c/hcpp-blynn.c"
grep -Fx 'enum{TOP=2048};' "$work/c/hcc1-blynn.c"

run BUILD_PRECISELY_UP=1
[ -x "$work/out/bin/precisely_up" ]
grep -Fx 'enum{TOP=2048};' "$work/out/generated/precisely_up.c"
reject 'BUILD_PRECISELY_UP must be 0 or 1' BUILD_PRECISELY_UP=yes
reject 'CROSSLY_TOP must be a canonical decimal' CROSSLY_TOP=04096
reject 'PRECISELY_TOP must be a canonical decimal' BUILD_PRECISELY_UP=1 PRECISELY_TOP=0
reject 'failed to generate' BAD_TOP=1024
for stage in crossly1 precisely_up; do
  status=0
  run BUILD_PRECISELY_UP=1 FAIL_STAGE="$stage" > "$work/rejected.log" 2>&1 || status=$?
  [ "$status" -eq 23 ]
done
printf 'portable Blynn ladder selection and TOP checks: OK\n'
