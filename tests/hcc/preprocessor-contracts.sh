# Sourced by compiler smoke; uses only its compiler paths and POSIX shell.
pp_contract_contains() {
  pp_pattern=$1
  pp_file=$2
  pp_found=0
  while IFS= read -r pp_line; do
    case "$pp_line" in *"$pp_pattern"*) pp_found=1; break ;; esac
  done < "$pp_file"
  if test "$pp_found" != 1; then
    echo "$pp_file: expected $pp_pattern" >&2
    exit 1
  fi
}

"$HCPP" "$TESTS_DIR/pp-contract-inactive.c" > pp-contract-inactive.i
pp_contract_contains 'int pp_contract_inactive ;' pp-contract-inactive.i
"$HCC1" --check pp-contract-inactive.i

"$HCPP" "$TESTS_DIR/pp-contract-macros.c" > pp-contract-macros.i
pp_contract_contains 'pp_contract_nested = ( ( ( ( 1 ) + 1 ) ) + 1 )' pp-contract-macros.i
pp_contract_contains 'pp_contract_suffix = ( ( 1 ) + 1 )' pp-contract-macros.i
pp_contract_contains 'int A ;' pp-contract-macros.i
pp_contract_contains 'SELF ( 1 )' pp-contract-macros.i
pp_contract_contains '2 * 9 * g' pp-contract-macros.i
pp_contract_contains 'one twothree four' pp-contract-macros.i
