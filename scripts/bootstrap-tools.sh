#!/usr/bin/env sh

set -eu

case $0 in
  */*) script_path=$0 ;;
  *) script_path=$(command -v "$0") || exit 1 ;;
esac
script_dir=${script_path%/*}
[ "$script_dir" = "$script_path" ] && script_dir=.
script_dir=$(CDPATH= cd "$script_dir" && pwd)
. "$script_dir/lib/bootstrap.sh"
repo_dir=$(repo_root_from_script_dir "$script_dir")
load_source_pins "$repo_dir"

require_cmd chmod
require_cmd cp
require_cmd find
require_cmd ln
require_cmd mkdir
require_cmd rm
require_cmd sed

out_dir=${OUT_DIR:-build/bootstrap-tools}
source_cache=${SOURCE_CACHE_DIR:-build/source-cache}

out_dir=$(abspath "$out_dir")
source_cache=$(abspath "$source_cache")

bin_dir=$out_dir/bin
artifact_dir=$out_dir/artifact
mkdir -p "$bin_dir" "$artifact_dir" "$source_cache"

have_toolchain() {
  command -v M2-Mesoplanet >/dev/null 2>&1 \
    && command -v M2-Planet >/dev/null 2>&1 \
    && command -v blood-elf >/dev/null 2>&1 \
    && command -v M1 >/dev/null 2>&1 \
    && command -v hex2 >/dev/null 2>&1 \
    && command -v kaem >/dev/null 2>&1
}

link_existing_tool() {
  name=$1
  src=$(command -v "$name")
  rm -f "$bin_dir/$name"
  ln -s "$src" "$bin_dir/$name"
}

if [ "${BOOTSTRAP_TOOLS_REBUILD:-0}" != 1 ] && have_toolchain; then
  msg "using existing stage0 tools from PATH"
  for tool in M2-Mesoplanet M2-Planet blood-elf M1 hex2 kaem; do
    link_existing_tool "$tool"
  done
  msg "bootstrap tools linked in $bin_dir"
  exit 0
fi

configure_stage0_arch() {
  case ${M2_ARCH:-amd64} in
    amd64 | x86_64)
      arch_dir=AMD64
      answer_file=amd64.answers
      arch_pin=AMD64
      ;;
    x86 | i386 | i486 | i586 | i686)
      arch_dir=x86
      answer_file=x86.answers
      arch_pin=X86
      ;;
    aarch64 | arm64)
      arch_dir=AArch64
      answer_file=aarch64.answers
      arch_pin=AARCH64
      ;;
    riscv32)
      arch_dir=riscv32
      answer_file=riscv32.answers
      arch_pin=RISCV32
      ;;
    riscv64)
      arch_dir=riscv64
      answer_file=riscv64.answers
      arch_pin=RISCV64
      ;;
    *) die "unsupported stage0 architecture: ${M2_ARCH:-amd64}" ;;
  esac
  eval "arch_url=\${STAGE0_POSIX_${arch_pin}_URL}"
  eval "arch_rev=\${STAGE0_POSIX_${arch_pin}_REV}"
  eval "arch_archive=\${STAGE0_POSIX_${arch_pin}_ARCHIVE_URL}"
}

copy_stage0_tool() {
  name=$1
  src=$stage0_bin/$name
  [ -x "$src" ] || die "stage0 did not produce $src"
  rm -f "$bin_dir/$name"
  cp "$src" "$bin_dir/$name"
  chmod 555 "$bin_dir/$name"
}

stage0_submodule() {
  dest=$1
  url=$2
  rev=$3
  archive_url=$4
  fetch_ref=${5:-}

  source_checkout "$dest" "$url" "$rev" "$stage0_src/$dest" "$archive_url" "$fetch_ref" 0
}

stage0_src=$source_cache/stage0-posix
stage0_work=$artifact_dir/stage0-posix
configure_stage0_arch

source_checkout stage0-posix "$STAGE0_POSIX_URL" "$STAGE0_POSIX_REV" "$stage0_src" "$STAGE0_POSIX_ARCHIVE_URL" "" 0
stage0_submodule "$arch_dir" "$arch_url" "$arch_rev" "$arch_archive"
stage0_submodule M2-Mesoplanet "$M2_MESOPLANET_URL" "$STAGE0_M2_MESOPLANET_REV" "$STAGE0_M2_MESOPLANET_ARCHIVE_URL"
stage0_submodule M2-Planet "$STAGE0_M2_PLANET_URL" "$STAGE0_M2_PLANET_REV" "$STAGE0_M2_PLANET_ARCHIVE_URL"
stage0_submodule M2libc "$M2LIBC_URL" "$STAGE0_M2LIBC_REV" "$STAGE0_M2LIBC_ARCHIVE_URL"
stage0_submodule bootstrap-seeds "$STAGE0_BOOTSTRAP_SEEDS_URL" "$STAGE0_BOOTSTRAP_SEEDS_REV" "$STAGE0_BOOTSTRAP_SEEDS_ARCHIVE_URL"
stage0_submodule mescc-tools "$MESCC_TOOLS_URL" "$MESCC_TOOLS_REV" "$MESCC_TOOLS_ARCHIVE_URL" "${MESCC_TOOLS_FETCH_REF:-}"
stage0_submodule mescc-tools-extra "$STAGE0_MESCC_TOOLS_EXTRA_URL" "$STAGE0_MESCC_TOOLS_EXTRA_REV" "$STAGE0_MESCC_TOOLS_EXTRA_ARCHIVE_URL"
copy_writable_tree "$stage0_src" "$stage0_work"

msg "run stage0-posix $arch_dir seed from hex0"
(
  cd "$stage0_work"
  "./bootstrap-seeds/POSIX/$arch_dir/kaem-optional-seed"
  "./$arch_dir/bin/sha256sum" -c "$answer_file"
)

stage0_bin=$stage0_work/$arch_dir/bin
for tool in M2-Mesoplanet M2-Planet blood-elf M1 hex2 kaem; do
  copy_stage0_tool "$tool"
done
msg "stage0 bootstrap tools complete: $bin_dir"
