{ runCommand, crossly, crossly1, precisely, preciselySeed, preciselyDebug,
  sourceBundle, commonObjects, minimalBootstrap, bootstrapShell, hccSrc }:

runCommand "blynn-top-tests" {
  nativeBuildInputs = [ minimalBootstrap.stage0-posix.mescc-tools ];
  M2_ARCH = minimalBootstrap.stage0-posix.m2libcArch;
  M2_OS = minimalBootstrap.stage0-posix.m2libcOS;
} ''
  . ${../scripts/lib/bootstrap.sh}
  ulimit -s unlimited
  cat > probe.hs <<'EOF'
  module Main where
  foreign import ccall "putchar_shim" putChar :: Char -> IO ()
  main = putChar 'T'
  EOF
  # Cover each compiler, but run the argument matrix and M2 execution only once.
  for compiler in ${crossly}/bin/crossly_up ${crossly1}/bin/crossly1 \
      ${precisely}/bin/precisely_up ${preciselySeed}/bin/precisely_up \
      ${preciselyDebug}/bin/precisely_up; do
    "$compiler" < probe.hs > default.c
    check_generated_top default.c 16777216
    "$compiler" top 1048576 < probe.hs > probe.c
    check_generated_top probe.c 1048576
    tail -n +3 default.c > default.body
    tail -n +3 probe.c > probe.body
    cmp default.body probe.body
    if "$compiler" top 01024 < probe.hs > rejected; then exit 1; fi
    grep -F 'TOP must be a canonical decimal word count' rejected
  done
  compiler=${crossly1}/bin/crossly1
  "$compiler" top 1048576 < probe.hs > probe.c
  compile_m2 probe.c probe
  test "$(./probe)" = T
  for top in 1024 536870912; do
    "$compiler" top "$top" < probe.hs > probe.c
    check_generated_top probe.c "$top"
  done
  for top in "" 0 1023 01024 -1 +1024 '1<<24' 536870913 999999999999999999999; do
    if "$compiler" top "$top" < probe.hs > rejected; then exit 1; fi
    grep -F 'TOP must be a canonical decimal word count' rejected
    if (validate_top TOP "$top") > rejected 2>&1; then exit 1; fi
    grep -F 'TOP must be a canonical decimal word count' rejected
  done
  if "$compiler" top < probe.hs > rejected; then exit 1; fi
  if "$compiler" top 1048576 extra < probe.hs > rejected; then exit 1; fi

  # Real portable generation with independent heaps; no second HCC assembly.
  export BOOTSTRAP_LIB=${../scripts/lib/bootstrap.sh}
  export HCC_BLYNN_SOURCES_DIR=${sourceBundle}/share/hcc-blynn-sources
  export HCC_BLYNN_OBJECTS_DIR=${commonObjects}/share/${commonObjects.pname}
  export BLYNN_COMPILER="$compiler" HCPP_TOP=67108864 HCC1_TOP=100663296 OUT_DIR="$out"
  ${bootstrapShell}/bin/sh ${../scripts/hcc-blynn-c.sh}
  check_generated_top "$out/hcpp-blynn.c" "$HCPP_TOP"
  check_generated_top "$out/hcc1-blynn.c" "$HCC1_TOP"
  export HCC_BLYNN_C_DIR="$out" HCC_DIR=${hccSrc} OUT_DIR="$PWD/bin-custom"
  for name in HCPP_TOP HCC1_TOP; do
    if env "$name=134217728" ${bootstrapShell}/bin/sh ${../scripts/hcc-blynn-bin.sh} > rejected 2>&1; then
      echo "binary stage silently accepted a late $name override" >&2
      exit 1
    fi
    grep -F 'with TOP=134217728' rejected
  done
''
