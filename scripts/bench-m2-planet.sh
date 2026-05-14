#!/usr/bin/env sh

set -eu

path_dir() {
  case $1 in
    */*) printf '%s\n' "${1%/*}" ;;
    *) printf '.\n' ;;
  esac
}

repo=$(CDPATH= cd "$(path_dir "$0")/.." && pwd)
out_dir=${1:-$(mktemp -d /tmp/hcc-m2-bench.XXXXXX)}
runs=${RUNS:-3}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'bench-m2: missing command: %s\n' "$1" >&2
    printf 'bench-m2: run with: nix develop -c %s\n' "$0" >&2
    exit 1
  }
}

need_cmd M2-Planet
need_cmd M2-Mesoplanet
need_cmd precisely_up
need_cmd jq
need_cmd time
need_cmd wc

m2_planet=${M2_PLANET:-$(command -v M2-Planet)}
m2_mesoplanet=${M2_MESOPLANET:-$(command -v M2-Mesoplanet)}
time_cmd=$(command -v time)
mescc_tools=${MESCC_TOOLS:-$(path_dir "$m2_planet")}
stage0_src=${STAGE0_SRC:-}
if [ -z "$stage0_src" ]; then
  m2_drv=$(nix path-info --derivation "$repo#m2.mesoplanet.gcc" 2>/dev/null)
  stage0_src=$(nix derivation show "$m2_drv" | jq -r '.[].env.src')
fi
m2libc=${M2LIBC_PATH:-$stage0_src/M2libc}

blynn_src=${BLYNN_SRC:-}
if [ -z "$blynn_src" ]; then
  base_file=$(ls /nix/store/*-blynn-compiler-hcc/inn/BasePrecisely.hs 2>/dev/null | head -n 1 || true)
  if [ -z "$base_file" ]; then
    printf 'bench-m2: set BLYNN_SRC to a blynn/compiler source tree with inn/BasePrecisely.hs\n' >&2
    exit 1
  fi
  blynn_src=$(path_dir "$(path_dir "$base_file")")
fi

blynn_compiler=${BLYNN_COMPILER:-}
if [ -z "$blynn_compiler" ]; then
  vm_path=$(ls /nix/store/*-blynn-compiler-0-unstable-2026-05-06/bin/vm 2>/dev/null | head -n 1 || true)
  if [ -n "$vm_path" ]; then
    blynn_compiler=$(path_dir "$(path_dir "$vm_path")")
  fi
fi
vm_src=${VM_SRC:-}
if [ -z "$vm_src" ]; then
  vm_src_file=$(ls /nix/store/*-oriansj-blynn-compiler-hcc/patty.hs 2>/dev/null | head -n 1 || true)
  if [ -n "$vm_src_file" ]; then
    vm_src=$(path_dir "$vm_src_file")
  fi
fi

mkdir -p "$out_dir"

log() {
  printf 'bench-m2: %s\n' "$*"
}

timed() {
  label=$1
  shift
  "$time_cmd" -f "$label elapsed=%e maxrss=%M" "$@"
}

micro_source() {
  style=$1
  count=$2
  path=$3
  i=0
  : > "$path"
  while [ "$i" -lt "$count" ]; do
    case "$style" in
      init)
        printf 'int f%d(){ int i = %d; i = i + 1; return i; }\n' "$i" "$i" >> "$path"
        ;;
      assign)
        printf 'int f%d(){ int i; i = %d; i = i + 1; return i; }\n' "$i" "$i" >> "$path"
        ;;
      for-init)
        printf 'int f%d(){ int sum = 0; for (int i = 0; i < 10; i = i + 1) sum = sum + i; return sum; }\n' "$i" >> "$path"
        ;;
      for-assign)
        printf 'int f%d(){ int sum = 0; int i; for (i = 0; i < 10; i = i + 1) sum = sum + i; return sum; }\n' "$i" >> "$path"
        ;;
      *)
        printf 'bench-m2: unknown style: %s\n' "$style" >&2
        exit 1
        ;;
    esac
    i=$((i + 1))
  done
  printf 'int main(){ return f%d(); }\n' $((count - 1)) >> "$path"
}

bench_micro() {
  style=$1
  count=$2
  src=$out_dir/micro-$style-$count.c
  m1=$out_dir/micro-$style-$count.M1
  micro_source "$style" "$count" "$src"
  "$m2_planet" --file "$src" --output "$m1.warm" --architecture amd64 --debug >/dev/null
  r=1
  while [ "$r" -le "$runs" ]; do
    rm -f "$m1"
    timed "micro $style $count run$r" \
      "$m2_planet" --file "$src" --output "$m1" --architecture amd64 --debug >/dev/null
    r=$((r + 1))
  done
  printf 'micro %s %s m1_bytes=%s m1_lines=%s\n' \
    "$style" "$count" "$(wc -c < "$m1")" "$(wc -l < "$m1")"
}

patch_top() {
  path=$1
  # Generated Precisely C uses enum{TOP=...}; larger programs need a larger heap.
  sed -i 's/enum{TOP=[0-9][0-9]*}/enum{TOP=134217728}/' "$path"
}

bench_precisely_case() {
  name=$1
  main=$2
  input=$3
  expected=$4
  hs=$out_dir/$name.hs
  c=$out_dir/$name.c
  bin=$out_dir/$name

  cat \
    "$blynn_src/inn/BasePrecisely.hs" \
    "$blynn_src/inn/System.hs" \
    "$repo/tests/hcc/precisely-dialect/$main" \
    > "$hs"

  r=1
  while [ "$r" -le "$runs" ]; do
    timed "precisely $name run$r" precisely_up < "$hs" > "$c"
    patch_top "$c"
    r=$((r + 1))
  done

  rm -f "$bin"
  "$time_cmd" -f "m2-mesoplanet $name elapsed=%e maxrss=%M" \
    env -i PATH="$mescc_tools" M2LIBC_PATH="$m2libc" TMPDIR="$out_dir" \
      "$m2_mesoplanet" --operating-system Linux --architecture amd64 \
      -f "$c" -f "$repo/hcc/cbits/hcc_runtime_m2.c" -o "$bin" >/dev/null

  if [ -n "$input" ]; then
    actual=$(printf '%s' "$input" | "$bin")
  else
    actual=$("$bin")
  fi
  if [ "$actual" != "$expected" ]; then
    printf 'bench-m2: %s expected "%s", got "%s"\n' "$name" "$expected" "$actual" >&2
    exit 1
  fi
  printf 'precisely-case %s c_bytes=%s c_lines=%s bin_bytes=%s\n' \
    "$name" "$(wc -c < "$c")" "$(wc -l < "$c")" "$(wc -c < "$bin")"
}

log "out=$out_dir"
log "m2_planet=$m2_planet"
log "m2_mesoplanet=$m2_mesoplanet"
log "m2libc=$m2libc"
log "blynn_src=$blynn_src"
if [ -n "$blynn_compiler" ]; then
  log "blynn_compiler=$blynn_compiler"
else
  log "blynn_compiler=<unset>; skipping VM raw-stage benchmark"
fi
if [ -n "$vm_src" ]; then
  log "vm_src=$vm_src"
else
  log "vm_src=<unset>; skipping VM raw-stage benchmark"
fi

for count in ${COUNTS:-100 1000}; do
  bench_micro init "$count"
  bench_micro assign "$count"
  bench_micro for-init "$count"
  bench_micro for-assign "$count"
done

bench_precisely_case where Where.hs "" "where: ok"
bench_precisely_case local-syntax LocalSyntax.hs "" "local-syntax: ok"
bench_precisely_case reverse-input ReverseInput.hs "stage0" "0egats"

if [ -n "$blynn_compiler" ] && [ -n "$vm_src" ]; then
  raw=$blynn_compiler/share/blynn-compiler/raw
  lonely_raw=$out_dir/vm-lonely-raw.txt
  patty_raw=$out_dir/vm-patty-raw.txt
  guardedly_raw=$out_dir/vm-guardedly-raw.txt

  timed "vm lonely-raw" \
    "$blynn_compiler/bin/vm" -l "$raw" -lf "$vm_src/effectively.hs" --redo -lf "$vm_src/lonely.hs" -o "$lonely_raw"
  printf 'vm lonely-raw bytes=%s lines=%s\n' "$(wc -c < "$lonely_raw")" "$(wc -l < "$lonely_raw")"

  timed "vm patty" \
    "$blynn_compiler/bin/vm" -f "$vm_src/patty.hs" --raw "$lonely_raw" --rts_c run -o "$patty_raw"
  printf 'vm patty bytes=%s lines=%s\n' "$(wc -c < "$patty_raw")" "$(wc -l < "$patty_raw")"

  timed "vm guardedly" \
    "$blynn_compiler/bin/vm" -f "$vm_src/guardedly.hs" --raw "$patty_raw" --rts_c run -o "$guardedly_raw"
  printf 'vm guardedly bytes=%s lines=%s\n' "$(wc -c < "$guardedly_raw")" "$(wc -l < "$guardedly_raw")"
fi
