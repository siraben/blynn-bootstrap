#!/usr/bin/env bash
# Reusable memory + time harness for hcc1 on tcc-expanded.c.
#
# Reports the same six numbers per run, derived from `+RTS -s` and GNU time -v:
#   elapsed   wall clock seconds
#   maxrss    kernel-measured peak RSS (KiB)
#   peakres   GHC -s "maximum residency" (bytes)
#   alloc     GHC -s "bytes allocated in the heap"
#   gcs       Gen0+Gen1 collection count
#   prodpct   productivity (mut time / total)
#
# Usage:
#   scripts/hcc-memory-bench.sh <hcc1-bin> <input.c> [label]
# Examples:
#   scripts/hcc-memory-bench.sh result/bin/hcc1 tcc-expanded.c baseline
#
# Output is one tab-separated line per run, suitable for paste-into-table.
# A `header` first arg prints just the header row.
set -eu

if [ "${1:-}" = "header" ]; then
  printf 'label\telapsed_s\tmaxrss_KiB\tpeakres_MB\talloc_GB\tgcs\tprodpct\tirhash\n'
  exit 0
fi

bin=${1:?hcc1 binary}
input=${2:?input .c}
label=${3:-run}

GNUTIME=${GNUTIME:-time}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

"$GNUTIME" -v -o "$tmp/time.log" \
  "$bin" --m1-ir -o "$tmp/out.hccir" "$input" \
  +RTS -s -RTS 2> "$tmp/rts.log" >/dev/null

elapsed=$(awk '/Elapsed \(wall/ {split($NF, a, ":"); n=length(a); if (n==2) print a[1]*60+a[2]; else print a[1]*3600+a[2]*60+a[3]}' "$tmp/time.log")
maxrss=$(awk '/Maximum resident set size/ {print $NF}' "$tmp/time.log")
peakres=$(awk '/maximum residency/ {gsub(",", "", $1); printf "%.1f\n", $1/1048576}' "$tmp/rts.log")
alloc=$(awk '/bytes allocated in the heap/ {gsub(",", "", $1); printf "%.2f\n", $1/1073741824}' "$tmp/rts.log")
gcs=$(awk '/colls,/ {gsub(",", "", $2); t += $2} END {print t}' "$tmp/rts.log")
prodpct=$(awk '/Productivity/ {print $2}' "$tmp/rts.log")
irhash=$(sha256sum "$tmp/out.hccir" | cut -c1-12)

printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$label" "$elapsed" "$maxrss" "$peakres" "$alloc" "$gcs" "$prodpct" "$irhash"
