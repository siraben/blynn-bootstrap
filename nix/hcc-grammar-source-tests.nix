{ runCommand, gnugrep, hcc, generatedC, generator, originalGenerator }:

runCommand "hcc-grammar-debug-source-tests" {
  nativeBuildInputs = [ gnugrep ];
} ''
  sources=${generatedC}/share/${generatedC.pname}
  for name in hcpp hcc1; do
    # The compiler derivation publishes exactly what it received; the heap and
    # allocator policy must already be present in the generator output.
    cmp "$sources/$name-blynn.c" ${hcc}/share/hcc-grammar-debug/$name-blynn.c
    grep -Fx 'enum{TOP=134217728};' "$sources/$name-blynn.c"
    grep -Fx '#define HCC_RTS_USE_EXTERNAL_ALLOC 1' "$sources/$name-blynn.c"
  done

  # Exercise the source-level option itself, and prove that without it this
  # isolated generator still emits byte-identical C to the original GHC one.
  input="$sources/hcpp-object-input.hs"
  ${generator}/bin/precisely_up m2-grammar-debug < "$input" > mode.c
  cmp "$sources/hcpp-blynn.c" mode.c
  ${generator}/bin/precisely-grammar-debug top 134217728 < "$input" > explicit.c
  cmp mode.c explicit.c
  ${generator}/bin/precisely_up < "$input" > default.c
  ${originalGenerator}/bin/precisely_up < "$input" > original.c
  cmp original.c default.c
  grep -Fx 'enum{TOP=16777216};' default.c
  if grep -Fx '#define HCC_RTS_USE_EXTERNAL_ALLOC 1' default.c; then
    echo 'grammar debug option leaked into default generator mode' >&2
    exit 1
  fi
  # One nondefault TOP checks mode dispatch; #31 owns the shared TOP matrix.
  ${generator}/bin/precisely_up top 1048576 < "$input" > custom.c
  ${originalGenerator}/bin/precisely_up top 1048576 < "$input" > original-custom.c
  cmp custom.c original-custom.c
  ${generator}/bin/precisely-grammar-debug top 1048576 < "$input" > grammar-custom.c
  grep -Fx 'enum{TOP=1048576};' grammar-custom.c
  grep -Fx '#define HCC_RTS_USE_EXTERNAL_ALLOC 1' grammar-custom.c
  reject() {
    status=0
    ${generator}/bin/precisely-grammar-debug "$@" </dev/null > rejected.out 2> rejected.err || status=$?
    test "$status" = 1
    grep -Fx 'TOP must be a canonical decimal word count in 1024..536870912' rejected.out
  }
  reject top 01024
  reject top
  reject top 1048576 extra
  reject unknown
  touch "$out"
''
