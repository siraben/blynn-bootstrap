#!/usr/bin/env bash
# Run from the flake root with Nix available. Query .drv references, not output
# closures: host compilers need not leave a runtime reference in their binaries.
set -euo pipefail
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

drv() { nix eval --raw ".#$1.drvPath"; }
debug=$(drv m2.planet.grammar-gcc-debug)
old_debug=$(drv m2.mesoplanet.gcc)
source=$(drv m2.planet.grammar-gcc-debug.src)
hcc_debug=$(drv hcc.ghc.precisely.grammar-gcc-debug)
generator=$(drv precisely.ghc.grammar-debug)
generator_source=$(drv precisely.ghc.grammar-debug.src)
nix-store --query --requisites "$debug" > "$work/debug"
grep -Fx "$debug" "$work/debug"
grep -Fx "$source" "$work/debug"
nix-store --query --requisites "$hcc_debug" > "$work/hcc-debug"
for required in "$debug" "$source" "$generator" "$generator_source"; do
  grep -Fx "$required" "$work/hcc-debug"
done
faithful_c=$(drv hcc.blynn.c.m2.precisely)
if grep -Fx "$faithful_c" "$work/hcc-debug"; then
  echo 'grammar HCC unexpectedly depends on faithful crossly C' >&2
  exit 1
fi

for attr in default hcc.m2.precisely.m2 tinycc.m2.precisely.m2; do
  root=$(drv "$attr")
  nix-store --query --requisites "$root" > "$work/inputs"
  grep -Fx "$root" "$work/inputs"
  for forbidden in "$debug" "$old_debug" "$source" "$hcc_debug" "$generator" "$generator_source"; do
    if grep -Fx "$forbidden" "$work/inputs"; then
      echo "host M2 grammar/debug dependency leaked into $attr: $forbidden" >&2
      exit 1
    fi
  done
  echo "faithful derivation inputs: $attr"
done
