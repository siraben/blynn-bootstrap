#!/bin/sh

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

abspath() {
  case $1 in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$(pwd)/$1" ;;
  esac
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
