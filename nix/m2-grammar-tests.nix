{ runCommand, gcc, bash, coreutils, diffutils, gnugrep, compiler, src }:

runCommand "m2-grammar-gcc-debug-tests" {
  nativeBuildInputs = [ gcc bash coreutils diffutils gnugrep ];
} ''
  export CC=${gcc}/bin/gcc
  bash ${../tests/m2-grammar/run.sh} \
    ${compiler}/bin/m2-planet-grammar-gcc-debug ${src} ${../tests/m2-grammar}
  touch "$out"
''
