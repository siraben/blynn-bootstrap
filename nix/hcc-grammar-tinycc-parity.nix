{ runCommand, native, faithful, grammar }:

runCommand "hcc-grammar-debug-tinycc-parity" { } ''
  mkdir -p "$out"
  native=${native}/share/tinycc-hcc-m1
  faithful=${faithful}/share/tinycc-hcc-m1
  grammar=${grammar}/share/tinycc-hcc-m1
  for file in tcc-expanded.c tcc.hccir tcc.M1 \
    tcc-bootstrap-support.i tcc-bootstrap-support.hccir tcc-bootstrap-support.M1 \
    tcc-final-overrides.i tcc-final-overrides.hccir tcc-final-overrides.M1
  do
    cmp "$native/$file" "$faithful/$file"
    cmp "$native/$file" "$grammar/$file"
    sha256sum "$native/$file" "$faithful/$file" "$grammar/$file" >> "$out/hashes"
    echo "native/faithful/grammar HCC parity: $file"
  done
''
