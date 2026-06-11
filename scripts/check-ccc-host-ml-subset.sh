#!/bin/sh
set -eu

src=${1:-ccc/host/ccc_host.ml}

pattern='= function|-> function|let [^=]*\?[A-Za-z_]|(^|[^A-Za-z0-9_])(assert|class|functor|land|lazy|lor|lsl|lsr|lxor|method|object|private|when)([^A-Za-z0-9_]|$)|^[[:space:]]*(external|include|module|open)[[:space:]]+|~[A-Za-z_][A-Za-z0-9_]*:|Bigarray\.|Buffer\.|Bytes\.|Digest\.|Format\.|Hashtbl\.|Lazy\.|List\.find_opt|Map\.|Marshal\.|Obj\.|Option\.is_some|Printf\.|Queue\.|Result\.|Scanf\.|Seq\.|Set\.|Stack\.|Stream\.|Unix\.|\( let\* \)'
host_api_pattern='Sys\.|open_in_bin|open_out_bin|close_in|close_in_noerr|close_out|close_out_noerr|input_char|output_string|(^|[^A-Za-z_])stdin([^A-Za-z_]|$)|(^|[^A-Za-z_])stdout([^A-Za-z_]|$)|(^|[^A-Za-z_])stderr([^A-Za-z_]|$)|print_string|prerr_endline|(^|[^A-Za-z_])exit[[:space:]]'

if command -v rg >/dev/null 2>&1; then
  if rg -n "$pattern" "$src"; then
    echo "ccc host should stay within the portable host-ML subset" >&2
    exit 1
  fi
  if rg -n "$host_api_pattern" "$src" | rg -v 'HOST-ML-BOUNDARY'; then
    echo "ccc host should keep direct host APIs behind HOST-ML-BOUNDARY wrappers" >&2
    exit 1
  fi
else
  if grep -nE "$pattern" "$src"; then
    echo "ccc host should stay within the portable host-ML subset" >&2
    exit 1
  fi
  if grep -nE "$host_api_pattern" "$src" | grep -v 'HOST-ML-BOUNDARY'; then
    echo "ccc host should keep direct host APIs behind HOST-ML-BOUNDARY wrappers" >&2
    exit 1
  fi
fi
