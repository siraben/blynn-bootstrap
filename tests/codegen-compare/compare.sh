#!/bin/sh

set -eu

path_dir() {
  case $1 in
    */*) printf '%s\n' "${1%/*}" ;;
    *) printf '.\n' ;;
  esac
}

repo=$(CDPATH= cd "$(path_dir "$0")/../.." && pwd)
case_dir=$repo/tests/codegen-compare
out_dir=${1:-$repo/build/codegen-compare}

mkdir -p "$out_dir"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'compare: missing %s; pass it through PATH or run from nix develop\n' "$1" >&2
    exit 1
  fi
}

smoke_derivation_json() {
  smoke_drv=$(nix path-info --derivation "$repo#tests.host.ghc.native.smoke.m1" 2>/dev/null || true)
  if [ -n "$smoke_drv" ]; then
    nix derivation show "$smoke_drv" 2>/dev/null || true
  fi
}

smoke_json=${SMOKE_DERIVATION_JSON:-$(smoke_derivation_json)}

if ! command -v M1 >/dev/null 2>&1 || ! command -v blood-elf >/dev/null 2>&1 || ! command -v hex2 >/dev/null 2>&1; then
  mescc_bin=$(printf '%s\n' "$smoke_json" | sed -n 's#.*\(/nix/store/[^":]*-mescc-tools-[^":]*/bin\).*#\1#p' | head -n 1)
  if [ -n "$mescc_bin" ]; then
    PATH=$mescc_bin:$PATH
    export PATH
  fi
fi

if [ -z "${M2LIBC_PATH:-}" ]; then
  M2LIBC_PATH=$(printf '%s\n' "$smoke_json" | sed -n 's#.*\(/nix/store/[^":]*-stage0-posix-[^":]*-source/M2libc\).*#\1#p' | head -n 1)
  export M2LIBC_PATH
fi

if [ -z "${HCC_BIN:-}" ]; then
  HCC_BIN=$(nix build "$repo#hcc.host.ghc.native" --no-link --print-out-paths)
fi

if [ -z "${M2_MESOPLANET:-}" ]; then
  if command -v M2-Mesoplanet >/dev/null 2>&1; then
    M2_MESOPLANET=$(command -v M2-Mesoplanet)
  else
    M2_BIN=$(nix build "$repo#m2.mesoplanet.gcc" --no-link --print-out-paths)
    M2_MESOPLANET=$M2_BIN/bin/M2-Mesoplanet
  fi
fi

need M1
need blood-elf
need hex2

hcpp=${HCPP:-$HCC_BIN/bin/hcpp}
hcc1=${HCC1:-$HCC_BIN/bin/hcc1}
hcc_m1=${HCC_M1:-$HCC_BIN/bin/hcc-m1}

if [ -z "${M2LIBC_PATH:-}" ]; then
  printf 'compare: set M2LIBC_PATH or run under nix develop\n' >&2
  exit 1
fi

printf 'case\tcompiler\tm1_lines\tm1_bytes\thccir_lines\thccir_bytes\tstatus\n' > "$out_dir/summary.tsv"

for src in \
  "$case_dir/scalar_branch.c" \
  "$case_dir/short_circuit_return.c" \
  "$case_dir/loop_sum.c"
do
  name=${src##*/}
  name=${name%.c}
  i=$out_dir/$name.i
  hccir=$out_dir/$name.hcc.hccir
  hcc_m1_out=$out_dir/$name.hcc.M1
  meso_tmp=$out_dir/$name.mesoplanet.tmp
  meso_m1_out=$out_dir/$name.mesoplanet.M1

  "$hcpp" "$src" > "$i"
  "$hcc1" --m1-ir -o "$hccir" "$i"
  "$hcc_m1" "$hccir" "$hcc_m1_out"

  rm -rf "$meso_tmp"
  mkdir -p "$meso_tmp"
  "$M2_MESOPLANET" \
    --operating-system Linux \
    --architecture amd64 \
    --dirty-mode \
    --temp-directory "$meso_tmp" \
    -f "$src" \
    -o "$meso_tmp/$name" \
    >"$meso_tmp/stdout" 2>"$meso_tmp/stderr"
  cp "$meso_tmp/M2-Planet-000000" "$meso_m1_out"

  printf '%s\thcc\t%s\t%s\t%s\t%s\tok\n' \
    "$name" \
    "$(wc -l < "$hcc_m1_out")" \
    "$(wc -c < "$hcc_m1_out")" \
    "$(wc -l < "$hccir")" \
    "$(wc -c < "$hccir")" \
    >> "$out_dir/summary.tsv"
  printf '%s\tm2-mesoplanet\t%s\t%s\t\t\tok\n' \
    "$name" \
    "$(wc -l < "$meso_m1_out")" \
    "$(wc -c < "$meso_m1_out")" \
    >> "$out_dir/summary.tsv"
done

src=$case_dir/local_aggregate.c
name=local_aggregate
i=$out_dir/$name.i
hccir=$out_dir/$name.hcc.hccir
hcc_m1_out=$out_dir/$name.hcc.M1
meso_tmp=$out_dir/$name.mesoplanet.tmp

"$hcpp" "$src" > "$i"
"$hcc1" --m1-ir -o "$hccir" "$i"
"$hcc_m1" "$hccir" "$hcc_m1_out"
printf '%s\thcc\t%s\t%s\t%s\t%s\tok\n' \
  "$name" \
  "$(wc -l < "$hcc_m1_out")" \
  "$(wc -c < "$hcc_m1_out")" \
  "$(wc -l < "$hccir")" \
  "$(wc -c < "$hccir")" \
  >> "$out_dir/summary.tsv"

rm -rf "$meso_tmp"
mkdir -p "$meso_tmp"
if "$M2_MESOPLANET" \
  --operating-system Linux \
  --architecture amd64 \
  --dirty-mode \
  --temp-directory "$meso_tmp" \
  -f "$src" \
  -o "$meso_tmp/$name" \
  >"$meso_tmp/stdout" 2>"$meso_tmp/stderr"
then
  cp "$meso_tmp/M2-Planet-000000" "$out_dir/$name.mesoplanet.M1"
  printf '%s\tm2-mesoplanet\t%s\t%s\t\t\tok\n' \
    "$name" \
    "$(wc -l < "$out_dir/$name.mesoplanet.M1")" \
    "$(wc -c < "$out_dir/$name.mesoplanet.M1")" \
    >> "$out_dir/summary.tsv"
else
  printf '%s\tm2-mesoplanet\t\t\t\t\trejected; see %s\n' "$name" "$meso_tmp/stderr" >> "$out_dir/summary.tsv"
fi

cat "$out_dir/summary.tsv"
