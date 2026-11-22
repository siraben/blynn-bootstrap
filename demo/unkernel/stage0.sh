#!/bin/sh
set -eu
cd /seed
# Run the upstream AArch64 ladder from hex0, stopping before unrelated extras.
sed '/^# Phase 16-23 /,$d' AArch64/kaem.run > AArch64/kaem.bootstrap
./hex0-seed AArch64/hex0_AArch64.hex0 AArch64/artifact/hex0
./AArch64/artifact/hex0 AArch64/kaem-minimal.hex0 AArch64/artifact/kaem-0
./AArch64/artifact/kaem-0 ./AArch64/mescc-tools-mini-kaem.kaem
./AArch64/bin/kaem --verbose --strict --file ./AArch64/kaem.bootstrap
for tool in kaem hex2 M1 blood-elf M2-Planet M2-Mesoplanet; do
  answer=$(grep "  AArch64/bin/$tool\$" aarch64.answers)
  printf '%s\n' "$answer" | sha256sum -c -
done
printf '%s\n' 'Stage0: all six tool hashes verified.'
