#!/bin/sh
set -eu

# Run from any directory; only maintained compiler/runtime C is in scope.
cd "$(dirname "$0")/.."
case "${1:-}" in
  '') set -- --dry-run --Werror ;;
  --fix) set -- -i ;;
  *) printf 'usage: %s [--fix]\n' "$0" >&2; exit 2 ;;
esac

# NUL delimiters also handle filenames containing spaces. Newly added files
# must be staged so local checks and CI use the same tracked-file scope.
git ls-files -z -- 'hcc/cbits/*.c' 'hcc/cbits/*.h' 'hcc/support/*.c' 'hcc/support/*.h' |
  xargs -0 -r clang-format --style=file "$@" --
