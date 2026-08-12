#!/bin/sh
# Target plumbing checks for the packaged CCC-as-HCC interface.
# Usage: sh ccc/tests/run-target-tests.sh HCPP HCC1
set -eu

HCPP=${1:?missing hcpp path}
HCC1=${2:?missing hcc1 path}
WORK=${TMPDIR:-/tmp}/ccc-target-tests.$$
trap 'rm -rf "$WORK"' EXIT INT TERM
mkdir -p "$WORK"

cat > "$WORK/input.c" <<'EOF'
long value;
int main(void) { return sizeof(value); }
EOF
"$HCPP" "$WORK/input.c" > "$WORK/input.i"

for target in amd64 aarch64 riscv64 i386; do
  "$HCC1" --target "$target" --m1-ir -o "$WORK/$target.hccir" "$WORK/input.i"
  grep -qx "T $target" "$WORK/$target.hccir" || {
    echo "target test: missing HCCIR target marker for $target" >&2
    exit 1
  }
done

# i386 has 32-bit long/pointer words; this catches a target flag that is
# accepted syntactically but silently lowered with the amd64 word size.
grep -qx 'z 4' "$WORK/i386.hccir" || {
  echo "target test: i386 long was not emitted as four bytes" >&2
  exit 1
}

echo "ccc target tests passed"
