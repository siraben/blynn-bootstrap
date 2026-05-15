#!/usr/bin/env sh

set -eu

msg() {
  printf '%s\n' "${BOOTSTRAP_LOG_NAME:-bootstrap}: $*" >&2
}

die() {
  printf '%s\n' "${BOOTSTRAP_LOG_NAME:-bootstrap}: error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

repo_root_from_script_dir() {
  _script_dir=$1
  (CDPATH= cd "$_script_dir/.." && pwd)
}

load_source_pins() {
  _repo_dir=$1
  _pins=${BOOTSTRAP_SOURCE_PINS:-$_repo_dir/data/bootstrap-sources.env}
  [ -f "$_pins" ] || die "missing source pins: $_pins"
  # shellcheck disable=SC1090
  . "$_pins"
}

abspath() {
  case $1 in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$(pwd)/$1" ;;
  esac
}

git_checkout() {
  _name=$1
  _url=$2
  _rev=$3
  _dest=$4
  _fetch_ref=${5:-$_rev}
  _submodules=${6:-1}

  if [ ! -d "$_dest/.git" ]; then
    rm -rf "$_dest"
    msg "init $_name"
    mkdir -p "$_dest"
    git -C "$_dest" init -q
    git -C "$_dest" remote add origin "$_url"
  fi
  msg "checkout $_name $_rev"
  git -C "$_dest" fetch --depth 1 origin "$_fetch_ref"
  git -C "$_dest" checkout -q FETCH_HEAD
  _head=$(git -C "$_dest" rev-parse HEAD)
  [ "$_head" = "$_rev" ] || die "$_name checkout resolved to $_head, expected $_rev"
  if [ "$_submodules" = 1 ] && [ -f "$_dest/.gitmodules" ]; then
    git -C "$_dest" submodule update --init --depth 1 --recursive
  fi
}

fetch_url() {
  _fetch_url=$1
  _fetch_dest=$2
  if command -v curl >/dev/null 2>&1; then
    curl -fL -o "$_fetch_dest" "$_fetch_url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$_fetch_dest" "$_fetch_url"
  else
    die "missing fetcher for $_fetch_url; install curl/wget, provide source dirs, or install git"
  fi
}

archive_checkout() {
  _name=$1
  _archive_url=$2
  _rev=$3
  _dest=$4
  _stamp=$_dest/.bootstrap-rev

  if [ -f "$_stamp" ] && [ "$(sed -n '1p' "$_stamp")" = "$_rev" ]; then
    return
  fi

  require_cmd tar
  _tmp=${TMPDIR:-/tmp}/bootstrap-archive-$$
  _archive=$_tmp/archive.tar.gz
  rm -rf "$_tmp"
  mkdir -p "$_tmp/src"
  msg "fetch $_name archive"
  fetch_url "$_archive_url" "$_archive"
  tar -xzf "$_archive" -C "$_tmp/src"
  _top=$(find "$_tmp/src" -mindepth 1 -maxdepth 1 -type d | sed -n '1p')
  [ -n "$_top" ] || die "archive for $_name did not contain a source directory"
  rm -rf "$_dest"
  mkdir -p "$_dest"
  cp -R "$_top/." "$_dest/"
  chmod -R u+w "$_dest"
  printf '%s\n' "$_rev" > "$_stamp"
  rm -rf "$_tmp"
}

source_checkout() {
  _name=$1
  _url=$2
  _rev=$3
  _dest=$4
  _archive_url=${5:-}
  _fetch_ref=${6:-}
  _submodules=${7:-1}

  if [ -n "$_archive_url" ] && { command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; }; then
    archive_checkout "$_name" "$_archive_url" "$_rev" "$_dest"
  elif command -v git >/dev/null 2>&1; then
    git_checkout "$_name" "$_url" "$_rev" "$_dest" "$_fetch_ref" "$_submodules"
  else
    die "cannot fetch $_name; provide the source directory, or install curl/wget or git"
  fi
}

copy_writable_tree() {
  _src=$1
  _dest=$2
  rm -rf "$_dest"
  cp -R "$_src" "$_dest"
  chmod -R u+w "$_dest"
}

append_file() {
  _src=$1
  _dest=$2
  if command -v cat >/dev/null 2>&1; then
    cat "$_src" >> "$_dest"
  else
    while IFS= read -r _line || [ -n "$_line" ]; do
      printf '%s\n' "$_line" >> "$_dest"
    done < "$_src"
  fi
}

compile_m2() {
  _m2_src=$1
  _m2_out=$2
  shift 2
  : "${M2_ARCH:=amd64}"
  : "${M2_OS:=Linux}"
  : "${M2_MESOPLANET:=M2-Mesoplanet}"
  msg "M2-Mesoplanet $_m2_src -> $_m2_out"
  "$M2_MESOPLANET" --operating-system "$M2_OS" --architecture "$M2_ARCH" \
    -f "$_m2_src" "$@" -o "$_m2_out"
  chmod 555 "$_m2_out"
}
