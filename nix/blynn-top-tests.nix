{ runCommand, crossly, crossly1, precisely, preciselySeed, preciselyDebug,
  sourceBundle, commonObjects, minimalBootstrap, bootstrapShell, hccSrc, m2libc }:

runCommand "blynn-top-tests" {
  nativeBuildInputs = [ minimalBootstrap.stage0-posix.mescc-tools ];
  M2_ARCH = minimalBootstrap.stage0-posix.m2libcArch;
  M2_OS = minimalBootstrap.stage0-posix.m2libcOS;
} ''
  . ${../scripts/lib/bootstrap.sh}
  ulimit -s unlimited
  mkdir -p "$out"
  cat > probe.hs <<'EOF'
  module Main where
  foreign import ccall "putchar_shim" putChar :: Char -> IO ()
  main = putChar 'T'
  EOF

  for compiler in ${crossly}/bin/crossly_up ${crossly1}/bin/crossly1 \
      ${precisely}/bin/precisely_up ${preciselySeed}/bin/precisely_up \
      ${preciselyDebug}/bin/precisely_up; do
    echo "checking TOP contract: $compiler"
    "$compiler" < probe.hs > default.c
    check_generated_top default.c 16777216
    for top in 1024 1048576 2097152 536870912; do
      echo "generating TOP=$top"
      "$compiler" top "$top" < probe.hs > probe.c
      check_generated_top probe.c "$top"
      # The enum is the only output difference, including in the older RTS2.
      tail -n +3 default.c > default.body
      tail -n +3 probe.c > probe.body
      cmp default.body probe.body
      case $top in
        1048576 | 2097152)
          rm -f probe
          compile_m2 probe.c probe
          test "$(./probe)" = T
          ;;
      esac
    done
    for top in "" 0 128 1023 01024 -1 +1024 1x24 '1<<24' '1024;bad' \
        536870913 999999999999999999999999; do
      if "$compiler" top "$top" < probe.hs > rejected; then
        echo "accepted invalid TOP: $compiler [$top]" >&2
        exit 1
      fi
      grep -F 'TOP must be a canonical decimal word count' rejected
    done
    if "$compiler" top < probe.hs > rejected; then exit 1; fi
    if "$compiler" top 1048576 extra < probe.hs > rejected; then exit 1; fi
  done

  export BOOTSTRAP_LIB=${../scripts/lib/bootstrap.sh}
  export HCC_BLYNN_SOURCES_DIR=${sourceBundle}/share/hcc-blynn-sources
  export HCC_BLYNN_OBJECTS_DIR=${commonObjects}/share/${commonObjects.pname}
  export BLYNN_COMPILER=${crossly1}/bin/crossly1
  export OUT_DIR="$PWD/default"
  ${bootstrapShell}/bin/sh ${../scripts/hcc-blynn-c.sh}
  check_generated_top default/hcpp-blynn.c 134217728
  check_generated_top default/hcc1-blynn.c 134217728
  export HCPP_TOP=67108864 HCC1_TOP=100663296 OUT_DIR="$PWD/custom"
  ${bootstrapShell}/bin/sh ${../scripts/hcc-blynn-c.sh}
  check_generated_top custom/hcpp-blynn.c "$HCPP_TOP"
  check_generated_top custom/hcc1-blynn.c "$HCC1_TOP"
  for program in hcpp hcc1; do
    tail -n +3 "default/$program-blynn.c" > default.body
    tail -n +3 "custom/$program-blynn.c" > custom.body
    cmp default.body custom.body
  done
  for name in HCPP_TOP HCC1_TOP; do
    for top in "" 0 01024 -1 '1<<24' 536870913 99999999999999999999999; do
      if env "$name=$top" ${bootstrapShell}/bin/sh ${../scripts/hcc-blynn-c.sh} > rejected 2>&1; then
        echo "portable generation accepted $name=[$top]" >&2
        exit 1
      fi
      grep -F "$name must be a canonical decimal word count" rejected
    done
  done
  export HCC_BLYNN_C_DIR="$PWD/custom" HCC_DIR=${hccSrc}
  export M2LIBC_PATH=${m2libc} OUT_DIR="$PWD/bin-custom"
  if HCPP_TOP=134217728 ${bootstrapShell}/bin/sh ${../scripts/hcc-blynn-bin.sh} > rejected 2>&1; then
    echo 'binary stage silently accepted a late TOP override' >&2
    exit 1
  fi
  grep -F 'with TOP=134217728' rejected
  ${bootstrapShell}/bin/sh ${../scripts/hcc-blynn-bin.sh}
  grep -Fx "enum{TOP=$HCPP_TOP};" bin-custom/artifact/hcpp-blynn.patched.c
  grep -Fx "enum{TOP=$HCC1_TOP};" bin-custom/artifact/hcc1-blynn.patched.c
  export HCPP="$PWD/bin-custom/bin/hcpp" HCC1="$PWD/bin-custom/bin/hcc1"
  export HCC_M1="$PWD/bin-custom/bin/hcc-m1" TESTS_DIR=${../tests/hcc}
  . ${../scripts/hcc-compiler-smoke.sh}
  cp custom/hcpp-blynn.c custom/hcc1-blynn.c "$out/"
''
