#!@bash@
# Executable-producing adapter for the host-built grammar fork, not Mesoplanet.
# Deliberately supports only the tested amd64/Linux subset of its old CLI.
set -euo pipefail

fail() { printf '%s\n' "m2-planet-grammar-gcc-debug: $*" >&2; exit 2; }
value() {
  [ "$#" -ge 2 ] && [ -n "$2" ] && [[ $2 != -* ]] || fail "$1 requires a value"
}
args=(--expand-includes --debug -I '@libc@')
files=0
output=
while [ "$#" -gt 0 ]; do
  case $1 in
    -f|--file|-o|--output|--architecture|--operating-system|-I|-D)
      value "$@"
      option=$1; argument=$2; shift 2 ;;
    --file=*|--output=*|--architecture=*|--operating-system=*)
      option=${1%%=*}; argument=${1#*=}; shift
      [ -n "$argument" ] || fail "$option requires a value" ;;
    *) fail "unsupported option: $1" ;;
  esac
  case $option in
    -f|--file) args+=(--file "$argument"); files=$((files + 1)) ;;
    -o|--output)
      [ -z "$output" ] || fail 'output specified more than once'
      output=$argument ;;
    --architecture)
      case $argument in amd64|x86_64) ;; *) fail "unsupported architecture: $argument" ;; esac ;;
    --operating-system)
      [ "$argument" = Linux ] || fail "unsupported operating system: $argument" ;;
    -I|-D) args+=("$option" "$argument") ;;
  esac
done
[ "$files" -gt 0 ] || fail 'at least one input file is required'
[ -n "$output" ] || fail 'an output file is required'

# No implicit current-directory bootstrappable.c or ambient PATH tools. Callers
# that need bootstrappable helpers must pass that source explicitly with -f.
work=$('@coreutils@/mktemp' -d)
trap '"@coreutils@/rm" -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 129' HUP
trap 'exit 143' TERM
'@compiler@' "${args[@]}" --architecture amd64 --output "$work/program.M1"
libc=libc-core.M1
while IFS= read -r line; do
  case $line in *:FUNCTION___init_malloc*) libc=libc-full.M1; break ;; esac
done < "$work/program.M1"
'@tools@/blood-elf' --file "$work/program.M1" --little-endian --64 --output "$work/program.blood"
'@tools@/M1' --file '@libc@/amd64/amd64_defs.M1' \
  --file "@libc@/amd64/$libc" --file "$work/program.M1" \
  --file "$work/program.blood" --output "$work/program.hex2" \
  --architecture amd64 --little-endian
'@tools@/hex2' --file '@libc@/amd64/ELF-amd64-debug.hex2' \
  --file "$work/program.hex2" --output "$work/program" \
  --architecture amd64 --base-address 0x00600000 --little-endian
'@coreutils@/install' -m555 -- "$work/program" "$output"
