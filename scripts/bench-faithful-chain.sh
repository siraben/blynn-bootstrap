#!/usr/bin/env bash

set -euo pipefail

if (( $# < 3 || $# > 4 )); then
  echo "usage: $0 REPO LABEL OUT_DIR [FLAKE_ATTR]" >&2
  exit 2
fi

repo=$1
label=$2
out_dir=$3
flake_attr=${4:-tinycc.m2.precisely.m2}
time_bin=${TIME_BIN:-$(type -P time)}
rg_bin=${RG_BIN:-$(type -P rg)}

mkdir -p "$out_dir"
top_drv=$(nix path-info --derivation --no-write-lock-file "$repo#$flake_attr")
drv_list="$out_dir/$label.drvs"
times="$out_dir/$label.tsv"
metadata="$out_dir/$label.meta"

nix-store -qR "$top_drv" \
  | "$rg_bin" '/nix/store/[a-z0-9]+-(oriansj-blynn-compiler-hcc|blynn-compiler-hcc|gnu-mes-libc-hcc|blynn-(pack-blobs|blob-|raw-|vm-|marginally-|methodically-|upstream-)|hcc-blynn-(sources|objs-m2-precisely|c-m2-precisely)|hcc-m2-precisely-m2-|tinycc-boot-hcc-m2-precisely-m2-).*\.drv$' \
  > "$drv_list"

{
  echo "label=$label"
  echo "repo=$(cd "$repo" && pwd)"
  echo "revision=$(git -C "$repo" rev-parse HEAD)"
  echo "flake_attr=$flake_attr"
  echo "top_drv=$top_drv"
  echo "derivation_count=$(wc -l < "$drv_list")"
  echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "nix_version=$(nix --version)"
  echo "kernel=$(uname -srmo)"
  echo "worktree_status_begin"
  git -C "$repo" status --short
  echo "worktree_status_end"
} > "$metadata"

# Keep substitution and dependency realization outside the timed region. The
# timed --check below rebuilds each selected derivation body serially and
# compares it with its already-realized output.
while IFS= read -r drv; do
  nix-store --realise --option max-jobs 1 --option cores 1 "$drv" >/dev/null
done < "$drv_list"

: > "$times"
while IFS= read -r drv; do
  store_name=${drv#/nix/store/}
  name=${store_name#*-}
  timing=$(mktemp)
  log="$out_dir/$label-${name%.drv}.log"
  echo "$label START $name"
  "$time_bin" -f '%e\t%U\t%S\t%M' -o "$timing" \
    nix-store --realise --check \
      --option max-jobs 1 \
      --option cores 1 \
      --option substitute false \
      "$drv" > "$log" 2>&1
  read -r elapsed user_time sys_time rss < "$timing"
  rm -f "$timing"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$label" "$name" "$elapsed" "$user_time" "$sys_time" "$rss" \
    | tee -a "$times"
done < "$drv_list"

awk -F '\t' -v label="$label" '
  { elapsed += $3; user_time += $4; sys_time += $5; if ($6 > rss) rss = $6 }
  END { printf "%s TOTAL\t%.2f\t%.2f\t%.2f\t%d\n", label, elapsed, user_time, sys_time, rss }
' "$times"
