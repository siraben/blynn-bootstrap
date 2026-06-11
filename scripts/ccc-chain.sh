#!/usr/bin/env sh
# Build the CCC toolchain from the stage0 tools alone (no host C compiler,
# no ML tooling): M2-Mesoplanet compiles the two C seeds, the staged ML
# bootstrap runs 02 -> 01 -> 03 -> 04 with a fixpoint check, every
# promoted source passes the mltc type-check gate, and the result is an
# hcc-compatible bin/ directory (hcpp/hcc1 wrappers over the VM plus the
# M2-built hcc-m1 backend) ready for scripts/tinycc-boot-hcc.sh.
#
# Inputs (environment):
#   OUT_DIR       output directory (default build/ccc-chain)
#   M2_ARCH M2_OS architecture/OS for M2-Mesoplanet (amd64/aarch64, Linux)
#   M2LIBC_PATH   stage0-posix M2libc (required, from bootstrap-tools)
# Requires M2-Mesoplanet on PATH.

set -eu

# the tree-walking mlc-interp recurses deeply in C; match the nix build
ulimit -s unlimited 2>/dev/null || true

case $0 in
  */*) script_path=$0 ;;
  *) script_path=$(command -v "$0") || exit 1 ;;
esac
script_dir=${script_path%/*}
[ "$script_dir" = "$script_path" ] && script_dir=.
script_dir=$(CDPATH= cd "$script_dir" && pwd)
. "$script_dir/lib/bootstrap.sh"
repo_dir=$(repo_root_from_script_dir "$script_dir")

require_cmd M2-Mesoplanet
require_cmd cp
require_cmd mkdir
require_cmd cat
require_cmd cmp

out_dir=${OUT_DIR:-build/ccc-chain}
out_dir=$(abspath "$out_dir")
ccc_dir=$repo_dir/ccc
work=$out_dir/work

mkdir -p "$out_dir/bin" "$out_dir/lib" "$work"
cd "$work"

msg "ccc-chain: M2 seeds (mzvm, mlc-interp)"
compile_m2 "$ccc_dir/vm/mzvm.c" mzvm
compile_m2 "$ccc_dir/seed/mlc-interp-seed.c" mlc-interp

stages=$ccc_dir/stages
run01() { ./mlc-interp "$stages/01-parenthetical.ml" "$1" "$2"; }

msg "ccc-chain: staged ML bootstrap"
./mlc-interp "$stages/02-ml0-compiler.ml" "$stages/03-adt-compiler.ml" 03.mzs
run01 03.mzs 03.mzbc
./mzvm 03.mzbc "$stages/04-pattern-compiler.ml" 04.mzs
run01 04.mzs 04.mzbc
./mzvm 04.mzbc "$stages/04-pattern-compiler.ml" 04b.mzs
run01 04b.mzs 04b.mzbc
cmp 04.mzbc 04b.mzbc
msg "ccc-chain: stage 04 self-compilation fixpoint holds"

# bytecode assembler so the large assemblies run on the GC-backed VM
./mzvm 04.mzbc "$stages/01-parenthetical.ml" 01.mzs
run01 01.mzs 01.mzbc
runasm() { ./mzvm 01.mzbc "$1" "$2"; }

msg "ccc-chain: mltc type-check gate"
./mzvm 04.mzbc "$ccc_dir/mlc/mltc.ml" mltc.mzs
runasm mltc.mzs mltc.mzbc
typecheck() { ./mzvm mltc.mzbc "$1"; }
typecheck "$ccc_dir/mlc/mltc.ml"
typecheck "$stages/01-parenthetical.ml"
typecheck "$stages/02-ml0-compiler.ml"
typecheck "$stages/03-adt-compiler.ml"
typecheck "$stages/04-pattern-compiler.ml"

msg "ccc-chain: ccc1 + ccpp bytecode (type-checked)"
cat "$ccc_dir"/cc/[0-9]*.ml "$ccc_dir/cc/dev/cc1main.ml" > ccc-cc1.ml
typecheck ccc-cc1.ml
./mzvm 04.mzbc ccc-cc1.ml ccc-cc1.mzs
runasm ccc-cc1.mzs ccc-cc1.mzbc
cat "$ccc_dir/cc/00-util.ml" "$ccc_dir/cc/05-prim.ml" "$ccc_dir/cc/10-lexer.ml" \
    "$ccc_dir/cc/12-symtab.ml" "$ccc_dir/cc/18-literal.ml" "$ccc_dir/cc/20-ast.ml" \
    "$ccc_dir/cc/22-constexpr.ml" "$ccc_dir/cc/70-preproc.ml" \
    "$ccc_dir/cc/72-include.ml" "$ccc_dir/cc/dev/cppmain.ml" > ccpp.ml
typecheck ccpp.ml
./mzvm 04.mzbc ccpp.ml ccpp.mzs
runasm ccpp.mzs ccpp.mzbc

msg "ccc-chain: M2 hcc-m1 backend"
mkdir -p cbits
cp "$repo_dir/hcc/cbits/hcc_m1.c" cbits/hcc_m1.c
cp "$repo_dir/hcc/cbits/hcc_m1_arch_aarch64.c" cbits/
cp "$repo_dir/hcc/cbits/hcc_m1_arch_riscv64.c" cbits/
compile_m2 cbits/hcc_m1.c hcc-m1

cp mzvm "$out_dir/bin/mzvm"
cp hcc-m1 "$out_dir/bin/hcc-m1"
cp 04.mzbc ccc-cc1.mzbc ccpp.mzbc "$out_dir/lib/"
chmod 555 "$out_dir/bin/mzvm" "$out_dir/bin/hcc-m1"

cat > "$out_dir/bin/hcpp" <<EOF
#!/bin/sh
exec "$out_dir/bin/mzvm" "$out_dir/lib/ccpp.mzbc" "\$@"
EOF

cat > "$out_dir/bin/hcc1" <<EOF
#!/bin/sh
out=""
input=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    -o) out=\$2; shift 2 ;;
    --m1-ir|--trace|-S|-c) shift ;;
    --target) shift 2 ;;
    -*) echo "hcc1: unsupported option: \$1" >&2; exit 1 ;;
    *) input=\$1; shift ;;
  esac
done
if [ -z "\$input" ] || [ -z "\$out" ]; then
  echo "usage: hcc1 --m1-ir -o FILE INPUT.i" >&2; exit 1
fi
exec "$out_dir/bin/mzvm" "$out_dir/lib/ccc-cc1.mzbc" "\$input" "\$out"
EOF
chmod 555 "$out_dir/bin/hcpp" "$out_dir/bin/hcc1"

msg "ccc-chain: done; hcc-compatible toolchain under $out_dir/bin"
