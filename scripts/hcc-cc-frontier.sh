#!/bin/sh
set -eu

die() {
  echo "hcc-cc-frontier: $*" >&2
  exit 1
}

bindir=$(CDPATH= cd "$(dirname "$0")" && pwd)
HCPP=${HCPP:-$bindir/hcpp}
HCC1=${HCC1:-$bindir/hcc1}
HCC_M1=${HCC_M1:-$bindir/hcc-m1}
target=${HCC_TARGET:-amd64}

mode=compile
input=
output=
pp_args=

append_pp_arg() {
  if test -z "$pp_args"; then
    pp_args=$1
  else
    pp_args="$pp_args $1"
  fi
}

while test $# -gt 0; do
  case "$1" in
    --help)
      echo "usage: hcc-cc-frontier [CC-FLAGS...] -c [-o OUTPUT] INPUT.c"
      exit 0
      ;;
    --target)
      test $# -ge 2 || die "option $1 requires an argument"
      target=$2
      shift 2
      ;;
    --target=*)
      target=${1#--target=}
      shift
      ;;
    -c)
      mode=compile
      shift
      ;;
    -E)
      mode=preprocess
      shift
      ;;
    -S)
      mode=compile
      shift
      ;;
    -o)
      test $# -ge 2 || die "option $1 requires an argument"
      output=$2
      shift 2
      ;;
    -I|-D)
      test $# -ge 2 || die "option $1 requires an argument"
      value=$2
      append_pp_arg "$1"
      append_pp_arg "$value"
      shift 2
      ;;
    -I*|-D*)
      append_pp_arg "$1"
      shift
      ;;
    -isystem|-iquote)
      test $# -ge 2 || die "option $1 requires an argument"
      value=$2
      append_pp_arg -I
      append_pp_arg "$value"
      shift 2
      ;;
    -include)
      die "unsupported option: -include"
      ;;
    -MF|-MT|-MQ)
      test $# -ge 2 || die "option $1 requires an argument"
      shift 2
      ;;
    -MD|-MMD|-MP|-pipe|-nostdinc|-nostdlib|-static)
      shift
      ;;
    -O*|-g*|-std=*|-f*|-m*|-W*|-w|-pedantic|-ansi)
      shift
      ;;
    -*)
      die "unsupported option: $1"
      ;;
    *)
      if test -n "$input"; then
        die "multiple input files are not supported: $input $1"
      fi
      input=$1
      shift
      ;;
  esac
done

test -n "$input" || die "no input file"

stem=$(basename "$input")
case "$stem" in
  *.c) stem=${stem%.c} ;;
  *.i) stem=${stem%.i} ;;
  *.C) stem=${stem%.C} ;;
esac

case "$mode" in
  preprocess)
    if test -n "$output"; then
      # shellcheck disable=SC2086
      exec "$HCPP" $pp_args "$input" > "$output"
    fi
    # shellcheck disable=SC2086
    exec "$HCPP" $pp_args "$input"
    ;;
  compile) ;;
  *) die "internal mode error: $mode" ;;
esac

if test -z "$output"; then
  output="$stem.o"
fi

work=${TMPDIR:-/tmp}/hcc-cc-frontier.$$
rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT HUP INT TERM

preprocessed="$work/$stem.i"
ir="$work/$stem.hccir"
m1="$output.M1"

case "$input" in
  *.i)
    cp "$input" "$preprocessed"
    ;;
  *)
    # shellcheck disable=SC2086
    "$HCPP" $pp_args "$input" > "$preprocessed"
    ;;
esac

"$HCC1" --check "$preprocessed"
"$HCC1" --target "$target" --m1-ir -o "$ir" "$preprocessed"
"$HCC_M1" --target "$target" "$ir" "$m1"

{
  echo "kind: hcc-cc-frontier"
  echo "target: $target"
  echo "input: $input"
  echo "m1: $m1"
} > "$output"
