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
T parser_contract_after;
EOF
  "${HCC1:-hcc1}" --check parser-contract-parameters.c
)
