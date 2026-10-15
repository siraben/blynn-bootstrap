#!/bin/sh
# Source from compiler smoke, or run with HCC1 set. VLA parameter bounds are
# parse-only contracts; the runtime fixture covers supported executable cases.
(
  set -eu
  cat > parser-contract-parameters.c <<'EOF'
typedef char T;
int parser_contract_later(int T, int values[(T)]);
int parser_contract_nested(int (*callback)(int T), T value);
int parser_contract_own(int T[sizeof(T)]);
int parser_contract_static(int T, int values[static const (T)]);
int parser_contract_qualified(int T[const static sizeof(T)], int x[volatile restrict]);
int parser_contract_callback(int (*callback)(int T[static 1]), T value);
int parser_contract_unnamed(int [const static 1], int [static restrict 1]);
int parser_contract_dimensions(int values[static 2][3][4]);
int parser_contract_prototype_effect(int n, int values[static n++]);
T parser_contract_after;
EOF
  "${HCC1:-hcc1}" --check parser-contract-parameters.c

  # Parameter-only modifiers must not escape into object/inner dimensions.
  for source in \
    'int parser_contract_object[static 1];' \
    'int parser_contract_object[const static 1];' \
    'int parser_contract_object[static];' \
    'int parser_contract_object[const];' \
    'int parser_contract_bad(int a[2][static 1]);' \
    'int parser_contract_bad(int a[2][const]);' \
    'int parser_contract_bad(int a[static]);' \
    'int parser_contract_bad(int a[static static]);' \
    'int parser_contract_bad(int a[const static volatile]);' \
    'int parser_contract_bad(int n, int a[static n++]) { return n; }'
  do
    printf '%s\n' "$source" > parser-contract-invalid-array.c
    if "${HCC1:-hcc1}" --check parser-contract-invalid-array.c > parser-contract-invalid-array.out 2>&1; then
      printf 'unexpectedly accepted: %s\n' "$source" >&2
      exit 1
    fi
  done
)
